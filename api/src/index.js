import { randomInt } from 'node:crypto';
import express from 'express';
import rateLimit from 'express-rate-limit';
import bcrypt from 'bcryptjs';
import jwt from 'jsonwebtoken';
import { pool, migrate, cleanup } from './db.js';
import { sendMail, resetCodeEmail } from './mailer.js';

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
app.disable('x-powered-by');
app.use(express.json({ limit: '10kb' }));

// Journal minimal : méthode, route, statut, durée. Jamais le corps des
// requêtes (mots de passe) ni les coordonnées envoyées par l'app.
app.use((req, res, next) => {
  const start = process.hrtime.bigint();
  res.on('finish', () => {
    const ms = Number(process.hrtime.bigint() - start) / 1e6;
    const uid = req.uid ? ` uid=${String(req.uid).slice(0, 8)}` : '';
    console.log(
      `${req.method} ${req.path} ${res.statusCode} ${ms.toFixed(0)}ms${uid}`,
    );
  });
  next();
});

const wrap = (fn) => (req, res, next) => fn(req, res, next).catch(next);
const sign = (id) => jwt.sign({ sub: id }, JWT_SECRET, { expiresIn: '30d' });
// Retire aussi les caractères de contrôle (retours à la ligne, NUL…) qui
// polluent les logs et peuvent casser l'affichage côté app.
const clean = (v, max) =>
  String(v ?? '').replace(/[\u0000-\u001f\u007f]/g, ' ').trim().slice(0, max);

const authLimiter = rateLimit({
  windowMs: 15 * 60 * 1000,
  limit: 30,
  standardHeaders: true,
  legacyHeaders: false,
  message: { error: 'Trop de tentatives. Réessaie dans quelques minutes.' },
});

// Toutes les routes authentifiées sont limitées : sans ça, un compte peut
// marteler /location (qui déclenche une requête SQL coûteuse) ou énumérer
// les profils sans aucune limite.
const apiLimiter = rateLimit({
  windowMs: 60 * 1000,
  limit: 240,
  standardHeaders: true,
  legacyHeaders: false,
  message: { error: 'Trop de requêtes. Patiente un instant.' },
});

// /location déclenche checkAlarms() : quota plus serré (l'app envoie
// une position toutes les 2 minutes, soit 0,5 requête/min).
const locationLimiter = rateLimit({
  windowMs: 60 * 1000,
  limit: 20,
  standardHeaders: true,
  legacyHeaders: false,
  message: { error: 'Trop de mises à jour de position.' },
});

// Hash factice : garantit un temps de réponse comparable quand l'email
// n'existe pas, pour empêcher l'énumération des comptes par timing.
const DUMMY_HASH = '$2a$10$mBtYAfN3ZSYyJYKi7F1nU.8qP0kkMA5dSAsamBurVrrsVeE0k/mhe';

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

// Vérifie aussi la base : un moniteur externe doit voir la panne, pas un
// « ok » mensonger.
app.get('/health', async (_req, res) => {
  try {
    await pool.query('select 1');
    res.json({ ok: true });
  } catch (e) {
    console.error('Health check : base injoignable', e.message);
    res.status(503).json({ ok: false });
  }
});

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

const MAX_FAILED = 10;
const LOCK_MINUTES = 15;

app.post('/auth/login', authLimiter, wrap(async (req, res) => {
  const email = clean(req.body.email, 200).toLowerCase();
  const password = String(req.body.password ?? '');
  const { rows } = await pool.query(
    'select id, password_hash, failed_attempts, locked_until from users where email = $1',
    [email],
  );
  const user = rows[0];

  // Verrouillage temporaire par compte : la limite par IP ne protège pas
  // contre un bourrage ciblé depuis un réseau partagé (NAT de campus).
  if (user?.locked_until && new Date(user.locked_until) > new Date()) {
    return res
      .status(429)
      .json({ error: 'Trop d’essais. Réessaie dans quelques minutes.' });
  }

  // bcrypt.compare est toujours exécuté, même si l'email est inconnu :
  // sinon le temps de réponse révèle quels comptes existent.
  const hash = user ? user.password_hash : DUMMY_HASH;
  const ok = (await bcrypt.compare(password, hash)) && Boolean(user);

  if (!ok) {
    if (user) {
      const attempts = (user.failed_attempts ?? 0) + 1;
      const lock = attempts >= MAX_FAILED;
      await pool
        .query(
          lock
            ? 'update users set failed_attempts = 0, locked_until = now() + make_interval(mins => $2) where id = $1'
            : 'update users set failed_attempts = $2 where id = $1',
          lock ? [user.id, LOCK_MINUTES] : [user.id, attempts],
        )
        .catch((e) => console.error('Compteur d’échecs', e.message));
    }
    return res.status(401).json({ error: 'Email ou mot de passe incorrect.' });
  }

  if (user.failed_attempts > 0 || user.locked_until) {
    await pool
      .query(
        'update users set failed_attempts = 0, locked_until = null where id = $1',
        [user.id],
      )
      .catch(() => {});
  }
  res.json({ token: sign(user.id) });
}));

// ───────────── Mot de passe oublié ─────────────
// Un code à 6 chiffres plutôt qu'un lien : l'app n'a pas de liens profonds,
// et un code se recopie à la main sans dépendre d'un domaine vérifié.
const RESET_TTL_MINUTES = 15;
const MAX_RESET_ATTEMPTS = 5;

app.post('/auth/forgot', authLimiter, wrap(async (req, res) => {
  const email = clean(req.body.email, 200).toLowerCase();
  // Réponse identique dans tous les cas : sinon la route dit quels emails
  // sont inscrits.
  const generic = {
    ok: true,
    message: 'Si un compte existe, un code vient d’être envoyé.',
  };
  if (!EMAIL_RE.test(email)) return res.json(generic);

  const { rows } = await pool.query('select id from users where email = $1', [email]);
  if (rows.length === 0) return res.json(generic);

  const code = String(randomInt(0, 1_000_000)).padStart(6, '0');
  const codeHash = await bcrypt.hash(code, 10);
  await pool.query(
    `insert into password_resets (user_id, code_hash, expires_at)
     values ($1, $2, now() + make_interval(mins => $3))
     on conflict (user_id) do update
       set code_hash = excluded.code_hash,
           expires_at = excluded.expires_at,
           attempts = 0`,
    [rows[0].id, codeHash, RESET_TTL_MINUTES],
  );
  await sendMail({ to: email, ...resetCodeEmail(code) });
  res.json(generic);
}));

app.post('/auth/reset', authLimiter, wrap(async (req, res) => {
  const email = clean(req.body.email, 200).toLowerCase();
  const code = clean(req.body.code, 10);
  const password = String(req.body.password ?? '');
  const invalid = { error: 'Code invalide ou expiré.' };

  if (!EMAIL_RE.test(email) || !/^\d{6}$/.test(code)) {
    return res.status(400).json(invalid);
  }
  if (password.length < 6 || password.length > 200) {
    return res.status(400).json({
      error: 'Le mot de passe doit contenir au moins 6 caractères.',
    });
  }

  const { rows } = await pool.query(
    `select pr.code_hash, pr.expires_at, pr.attempts, u.id as user_id
     from password_resets pr
     join users u on u.id = pr.user_id
     where u.email = $1`,
    [email],
  );
  const row = rows[0];
  const expired = row && new Date(row.expires_at) < new Date();
  if (!row || expired || row.attempts >= MAX_RESET_ATTEMPTS) {
    return res.status(400).json(invalid);
  }
  if (!(await bcrypt.compare(code, row.code_hash))) {
    await pool.query(
      'update password_resets set attempts = attempts + 1 where user_id = $1',
      [row.user_id],
    );
    return res.status(400).json(invalid);
  }

  const hash = await bcrypt.hash(password, 10);
  await pool.query(
    'update users set password_hash = $2, failed_attempts = 0, locked_until = null where id = $1',
    [row.user_id, hash],
  );
  await pool.query('delete from password_resets where user_id = $1', [row.user_id]);
  // Connecté directement après la réinitialisation : une saisie de moins.
  res.json({ ok: true, token: sign(row.user_id) });
}));

// ───────────── Profil ─────────────
const PUBLIC_FIELDS = 'id, first_name, faculty, promotion, discoverable';

app.get('/me', auth, apiLimiter, wrap(async (req, res) => {
  const { rows } = await pool.query(
    `select ${PUBLIC_FIELDS} from users where id = $1`,
    [req.uid],
  );
  if (rows.length === 0) return res.status(404).json({ error: 'Compte introuvable.' });
  res.json(rows[0]);
}));

app.put('/me', auth, apiLimiter, wrap(async (req, res) => {
  const firstName = clean(req.body.first_name, 50);
  const faculty = clean(req.body.faculty, 80) || null;
  const promotion = clean(req.body.promotion, 40) || null;
  if (!firstName) return res.status(400).json({ error: 'Le prénom est obligatoire.' });

  // discoverable est optionnel : s'il est absent, on ne change rien.
  const discoverable =
    typeof req.body.discoverable === 'boolean' ? req.body.discoverable : null;

  await pool.query(
    `update users
     set first_name = $2,
         faculty = $3,
         promotion = $4,
         discoverable = coalesce($5, discoverable)
     where id = $1`,
    [req.uid, firstName, faculty, promotion, discoverable],
  );
  res.json({ ok: true });
}));

/**
 * Suppression du compte (droit à l'effacement).
 * Le mot de passe est redemandé : un téléphone déverrouillé ne doit pas
 * suffire à effacer un compte.
 */
app.delete('/me', auth, apiLimiter, wrap(async (req, res) => {
  const password = String(req.body.password ?? '');
  const { rows } = await pool.query(
    'select password_hash from users where id = $1',
    [req.uid],
  );
  if (rows.length === 0) return res.status(404).json({ error: 'Compte introuvable.' });
  if (!(await bcrypt.compare(password, rows[0].password_hash))) {
    return res.status(403).json({ error: 'Mot de passe incorrect.' });
  }
  // crushes, locations, alarms et password_resets partent en cascade.
  await pool.query('delete from users where id = $1', [req.uid]);
  res.json({ ok: true });
}));

// Annuaire du campus : champs publics uniquement.
app.get('/profiles', auth, apiLimiter, wrap(async (req, res) => {
  const { rows } = await pool.query(
    `select id, first_name, faculty, promotion
     from users
     where id <> $1 and first_name <> '' and discoverable
     order by first_name limit 500`,
    [req.uid],
  );
  res.json(rows);
}));

// ───────────── Crushes secrets ─────────────
// Renvoie uniquement MES choix. Aucune route ne révèle qui m'a choisi.
app.get('/crushes', auth, apiLimiter, wrap(async (req, res) => {
  const { rows } = await pool.query(
    'select to_user from crushes where from_user = $1',
    [req.uid],
  );
  res.json(rows.map((r) => r.to_user));
}));

const validTarget = (req, res) => {
  const target = req.params.id;
  if (!UUID_RE.test(target) || target === req.uid) {
    res.status(400).json({ error: 'Choix invalide.' });
    return null;
  }
  return target;
};

/**
 * Choisir / retirer quelqu'un.
 *
 * POST et DELETE sont idempotents : envoyer deux fois « choisir » ne peut
 * pas annuler le choix. L'ancienne route /toggle inversait l'état à chaque
 * appel, ce qui produisait de vrais bugs quand l'utilisateur touchait deux
 * fois le bouton (ou quand l'app réessayait après un timeout réseau).
 */
app.post('/crushes/:id', auth, apiLimiter, wrap(async (req, res) => {
  const target = validTarget(req, res);
  if (!target) return;
  try {
    await pool.query(
      'insert into crushes (from_user, to_user) values ($1, $2) on conflict do nothing',
      [req.uid, target],
    );
  } catch (e) {
    if (e.code === '23503') return res.status(404).json({ error: 'Profil introuvable.' });
    throw e;
  }
  await checkAlarms(req.uid);
  res.json({ active: true });
}));

app.delete('/crushes/:id', auth, apiLimiter, wrap(async (req, res) => {
  const target = validTarget(req, res);
  if (!target) return;
  await pool.query(
    'delete from crushes where from_user = $1 and to_user = $2',
    [req.uid, target],
  );
  res.json({ active: false });
}));

// Conservée pour les versions déjà installées de l'app. Dépréciée.
app.post('/crushes/:id/toggle', auth, apiLimiter, wrap(async (req, res) => {
  const target = validTarget(req, res);
  if (!target) return;
  const del = await pool.query(
    'delete from crushes where from_user = $1 and to_user = $2',
    [req.uid, target],
  );
  if (del.rowCount > 0) return res.json({ active: false });

  try {
    await pool.query(
      'insert into crushes (from_user, to_user) values ($1, $2) on conflict do nothing',
      [req.uid, target],
    );
  } catch (e) {
    if (e.code === '23503') return res.status(404).json({ error: 'Profil introuvable.' });
    throw e;
  }
  await checkAlarms(req.uid);
  res.json({ active: true });
}));

// ───────────── Position (jamais exposée) ─────────────
app.post('/location', auth, locationLimiter, wrap(async (req, res) => {
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
app.get('/alarms', auth, apiLimiter, wrap(async (req, res) => {
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
await cleanup().catch((e) => console.error('Purge initiale échouée', e));

// Purge toutes les 6 h. unref() : la tâche ne bloque pas l'arrêt du process.
setInterval(() => {
  cleanup().catch((e) => console.error('Purge échouée', e));
}, 6 * 60 * 60 * 1000).unref();

app.listen(PORT, () => console.log(`Ding API sur le port ${PORT}`));
