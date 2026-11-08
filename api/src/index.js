import express from 'express';
import rateLimit from 'express-rate-limit';
import bcrypt from 'bcryptjs';
import jwt from 'jsonwebtoken';
import { pool, migrate } from './db.js';

const PORT = process.env.PORT || 3000;
const JWT_SECRET = process.env.JWT_SECRET;
const RADIUS = Number(process.env.ALARM_RADIUS_METERS || 150);
const DOMAIN = (process.env.ALLOWED_EMAIL_DOMAIN || '').trim().toLowerCase();

if (!JWT_SECRET || !process.env.DATABASE_URL) {
  console.error('DATABASE_URL et JWT_SECRET sont obligatoires.');
  process.exit(1);
}

const EMAIL_RE = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

const app = express();
app.set('trust proxy', 1);
app.use(express.json({ limit: '10kb' }));

const wrap = (fn) => (req, res, next) => fn(req, res, next).catch(next);
const sign = (id) => jwt.sign({ sub: id }, JWT_SECRET, { expiresIn: '30d' });
const clean = (v, max) => String(v ?? '').trim().slice(0, max);

const authLimiter = rateLimit({
  windowMs: 15 * 60 * 1000,
  limit: 30,
  standardHeaders: true,
  legacyHeaders: false,
  message: { error: 'Trop de tentatives. Réessaie dans quelques minutes.' },
});

function auth(req, res, next) {
  const h = req.headers.authorization || '';
  const token = h.startsWith('Bearer ') ? h.slice(7) : null;
  if (!token) return res.status(401).json({ error: 'Non connecté.' });
  try {
    req.uid = jwt.verify(token, JWT_SECRET).sub;
    next();
  } catch {
    res.status(401).json({ error: 'Session expirée. Reconnecte-toi.' });
  }
}

/**
 * Crée une alarme pour chaque crush réciproque proche de l'utilisateur
 * (positions de moins de 15 min, distance <= RADIUS, 1 alarme max par heure et par paire).
 */
async function checkAlarms(uid) {
  await pool.query(
    `insert into alarms (user_a, user_b, bucket)
     select least(c1.from_user, c1.to_user),
            greatest(c1.from_user, c1.to_user),
            floor(extract(epoch from now()) / 3600)::bigint
     from crushes c1
     join crushes c2 on c2.from_user = c1.to_user and c2.to_user = c1.from_user
     join locations me on me.user_id = c1.from_user
     join locations o on o.user_id = c1.to_user
     where c1.from_user = $1
       and me.updated_at > now() - interval '15 minutes'
       and o.updated_at > now() - interval '15 minutes'
       and 2 * 6371000 * asin(least(1, sqrt(
             power(sin(radians(o.lat - me.lat) / 2), 2) +
             cos(radians(me.lat)) * cos(radians(o.lat)) *
             power(sin(radians(o.lng - me.lng) / 2), 2)
           ))) <= $2
     on conflict do nothing`,
    [uid, RADIUS],
  );
}

app.get('/health', (_req, res) => res.json({ ok: true }));

// ───────────── Authentification ─────────────
app.post('/auth/signup', authLimiter, wrap(async (req, res) => {
  const email = clean(req.body.email, 200).toLowerCase();
  const password = String(req.body.password ?? '');
  const firstName = clean(req.body.first_name, 50);

  if (!EMAIL_RE.test(email) || password.length < 6 || password.length > 200 || !firstName) {
    return res.status(400).json({
      error: 'Prénom, email valide et mot de passe de 6 caractères minimum requis.',
    });
  }
  if (DOMAIN && !email.endsWith(`@${DOMAIN}`)) {
    return res.status(400).json({ error: `Utilise ton adresse @${DOMAIN}.` });
  }

  const hash = await bcrypt.hash(password, 10);
  try {
    const { rows } = await pool.query(
      'insert into users (email, password_hash, first_name) values ($1, $2, $3) returning id',
      [email, hash, firstName],
    );
    res.status(201).json({ token: sign(rows[0].id) });
  } catch (e) {
    if (e.code === '23505') {
      return res.status(409).json({ error: 'Un compte existe déjà avec cet email.' });
    }
    throw e;
  }
}));

app.post('/auth/login', authLimiter, wrap(async (req, res) => {
  const email = clean(req.body.email, 200).toLowerCase();
  const password = String(req.body.password ?? '');
  const { rows } = await pool.query(
    'select id, password_hash from users where email = $1',
    [email],
  );
  const ok = rows.length > 0 && (await bcrypt.compare(password, rows[0].password_hash));
  if (!ok) return res.status(401).json({ error: 'Email ou mot de passe incorrect.' });
  res.json({ token: sign(rows[0].id) });
}));

// ───────────── Profil ─────────────
app.get('/me', auth, wrap(async (req, res) => {
  const { rows } = await pool.query(
    'select id, first_name, faculty, promotion from users where id = $1',
    [req.uid],
  );
  if (rows.length === 0) return res.status(404).json({ error: 'Compte introuvable.' });
  res.json(rows[0]);
}));

app.put('/me', auth, wrap(async (req, res) => {
  const firstName = clean(req.body.first_name, 50);
  const faculty = clean(req.body.faculty, 80) || null;
  const promotion = clean(req.body.promotion, 40) || null;
  if (!firstName) return res.status(400).json({ error: 'Le prénom est obligatoire.' });
  await pool.query(
    'update users set first_name = $2, faculty = $3, promotion = $4 where id = $1',
    [req.uid, firstName, faculty, promotion],
  );
  res.json({ ok: true });
}));

// Annuaire du campus : champs publics uniquement.
app.get('/profiles', auth, wrap(async (req, res) => {
  const { rows } = await pool.query(
    `select id, first_name, faculty, promotion
     from users where id <> $1 and first_name <> ''
     order by first_name limit 500`,
    [req.uid],
  );
  res.json(rows);
}));

// ───────────── Crushes secrets ─────────────
// Renvoie uniquement MES choix. Aucune route ne révèle qui m'a choisi.
app.get('/crushes', auth, wrap(async (req, res) => {
  const { rows } = await pool.query(
    'select to_user from crushes where from_user = $1',
    [req.uid],
  );
  res.json(rows.map((r) => r.to_user));
}));

app.post('/crushes/:id/toggle', auth, wrap(async (req, res) => {
  const target = req.params.id;
  if (!UUID_RE.test(target) || target === req.uid) {
    return res.status(400).json({ error: 'Choix invalide.' });
  }
  const del = await pool.query(
    'delete from crushes where from_user = $1 and to_user = $2',
    [req.uid, target],
  );
  if (del.rowCount > 0) return res.json({ active: false });

  try {
    await pool.query(
      'insert into crushes (from_user, to_user) values ($1, $2)',
      [req.uid, target],
    );
  } catch (e) {
    if (e.code === '23503') return res.status(404).json({ error: 'Profil introuvable.' });
    if (e.code !== '23505') throw e;
  }
  await checkAlarms(req.uid);
  res.json({ active: true });
}));

// ───────────── Position (jamais exposée) ─────────────
app.post('/location', auth, wrap(async (req, res) => {
  const lat = Number(req.body.lat);
  const lng = Number(req.body.lng);
  if (!Number.isFinite(lat) || !Number.isFinite(lng) ||
      Math.abs(lat) > 90 || Math.abs(lng) > 180) {
    return res.status(400).json({ error: 'Position invalide.' });
  }
  await pool.query(
    `insert into locations (user_id, lat, lng, updated_at)
     values ($1, $2, $3, now())
     on conflict (user_id) do update
       set lat = excluded.lat, lng = excluded.lng, updated_at = now()`,
    [req.uid, lat, lng],
  );
  await checkAlarms(req.uid);
  res.json({ ok: true });
}));

// ───────────── Alarmes ─────────────
app.get('/alarms', auth, wrap(async (req, res) => {
  const { rows } = await pool.query(
    `select a.id as alarm_id, a.created_at,
            u.id as other_id, u.first_name as other_name, u.faculty as other_faculty
     from alarms a
     join users u on u.id = case when a.user_a = $1 then a.user_b else a.user_a end
     where a.user_a = $1 or a.user_b = $1
     order by a.created_at desc limit 100`,
    [req.uid],
  );
  res.json(rows);
}));

// eslint-disable-next-line no-unused-vars
app.use((err, _req, res, _next) => {
  const status = err.status && err.status < 500 ? err.status : 500;
  if (status === 500) console.error(err);
  res.status(status).json({
    error: status === 500 ? 'Erreur serveur.' : 'Requête invalide.',
  });
});

await migrate();
app.listen(PORT, () => console.log(`Ding API sur le port ${PORT}`));
