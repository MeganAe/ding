import { randomInt, randomUUID } from 'node:crypto';
import express from 'express';
import rateLimit from 'express-rate-limit';
import bcrypt from 'bcryptjs';
import jwt from 'jsonwebtoken';
import { pool, migrate, cleanup } from './db.js';
import { sendMail, resetCodeEmail } from './mailer.js';

const PORT = process.env.PORT || 3000;
const JWT_SECRET = process.env.JWT_SECRET;
const RADIUS = Number(process.env.ALARM_RADIUS_METERS || 150);
const alarmPollSeconds = Number(process.env.ALARM_POLL_SECONDS || 20);
const locationIntervalSeconds = Number(process.env.LOCATION_INTERVAL_SECONDS || 120);
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
// `jti` = identifiant unique du jeton : c'est ce qui permet de le révoquer
// (déconnexion, téléphone perdu) sans changer le secret de signature.
const sign = (id) =>
  jwt.sign({ sub: id, jti: randomUUID() }, JWT_SECRET, { expiresIn: '30d' });
// Retire aussi les caractères de contrôle (retours à la ligne, NUL…) qui
// polluent les logs et peuvent casser l'affichage côté app.
const clean = (v, max) =>
  String(v ?? '').replace(/[\u0000-\u001f\u007f]/g, ' ').trim().slice(0, max);

// Les quotas sont réglables par l'environnement : les tests de parcours créent
// beaucoup de comptes en quelques secondes, la production garde les défauts.
const authLimiter = rateLimit({
  windowMs: 15 * 60 * 1000,
  limit: Number(process.env.AUTH_RATE_LIMIT || 30),
  standardHeaders: true,
  legacyHeaders: false,
  message: { error: 'Trop de tentatives. Réessaie dans quelques minutes.' },
});

// Toutes les routes authentifiées sont limitées : sans ça, un compte peut
// marteler /location (qui déclenche une requête SQL coûteuse) ou énumérer
// les profils sans aucune limite.
const apiLimiter = rateLimit({
  windowMs: 60 * 1000,
  limit: Number(process.env.API_RATE_LIMIT || 240),
  standardHeaders: true,
  legacyHeaders: false,
  message: { error: 'Trop de requêtes. Patiente un instant.' },
});

// /location déclenche checkAlarms() : quota plus serré (l'app envoie
// une position toutes les 2 minutes, soit 0,5 requête/min).
const locationLimiter = rateLimit({
  windowMs: 60 * 1000,
  limit: Number(process.env.LOCATION_RATE_LIMIT || 20),
  standardHeaders: true,
  legacyHeaders: false,
  message: { error: 'Trop de mises à jour de position.' },
});

// Hash factice : garantit un temps de réponse comparable quand l'email
// n'existe pas, pour empêcher l'énumération des comptes par timing.
const DUMMY_HASH = '$2a$10$mBtYAfN3ZSYyJYKi7F1nU.8qP0kkMA5dSAsamBurVrrsVeE0k/mhe';

async function auth(req, res, next) {
  const h = req.headers.authorization || '';
  const token = h.startsWith('Bearer ') ? h.slice(7) : null;
  if (!token) return res.status(401).json({ error: 'Non connecté.' });

  let payload;
  try {
    payload = jwt.verify(token, JWT_SECRET);
  } catch {
    return res.status(401).json({ error: 'Session expirée. Reconnecte-toi.' });
  }

  // Les jetons émis avant l'arrivée des jetons révocables n'ont pas de jti :
  // on les laisse passer (ils expireront d'eux-mêmes), sinon une mise à jour
  // du serveur déconnecterait tout le monde d'un coup.
  if (payload.jti) {
    try {
      const { rowCount } = await pool.query(
        'select 1 from revoked_tokens where jti = $1',
        [payload.jti],
      );
      if (rowCount > 0) {
        return res
          .status(401)
          .json({ error: 'Session fermée. Reconnecte-toi.' });
      }
    } catch (e) {
      return next(e);
    }
  }

  req.uid = payload.sub;
  req.jti = payload.jti ?? null;
  req.tokenExp = payload.exp ?? null;
  next();
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
       and not exists (
         select 1 from blocks b
         where (b.user_id = c1.from_user and b.blocked_id = c1.to_user)
            or (b.user_id = c1.to_user and b.blocked_id = c1.from_user)
       )
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

// Réglages publics : l'app les lit au démarrage au lieu de garder sa propre
// copie du rayon d'alarme et des intervalles. Si l'API change un jour de
// valeur, les téléphones suivent sans mise à jour.
app.get('/config', (_req, res) => {
  res.json({
    alarm_radius_meters: RADIUS,
    alarm_poll_seconds: Math.round(alarmPollSeconds),
    location_interval_seconds: Math.round(locationIntervalSeconds),
  });
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

/**
 * Déconnexion : le jeton est révoqué côté serveur, donc il ne sert plus à
 * rien même si quelqu'un l'a copié (téléphone perdu, sauvegarde volée).
 */
app.post('/auth/logout', auth, apiLimiter, wrap(async (req, res) => {
  if (req.jti) {
    await pool.query(
      `insert into revoked_tokens (jti, user_id, expires_at)
       values ($1, $2, to_timestamp($3))
       on conflict do nothing`,
      [req.jti, req.uid, req.tokenExp ?? Math.floor(Date.now() / 1000) + 60],
    );
  }
  res.json({ ok: true });
}));

// ───────────── Profil ─────────────
// L'email n'est jamais exposé aux autres : il n'apparaît que dans /me.
const PRIVATE_FIELDS = 'id, email, first_name, faculty, promotion, discoverable';

app.get('/me', auth, apiLimiter, wrap(async (req, res) => {
  const { rows } = await pool.query(
    `select ${PRIVATE_FIELDS} from users where id = $1`,
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

/**
 * Annuaire du campus : champs publics uniquement, par pages.
 *
 * - `q`      : début du prénom (insensible à la casse). Vide = tout.
 * - `limit`  : 1 à 100, 50 par défaut.
 * - `offset` : à passer avec le `next_offset` de la page précédente.
 *
 * Les personnes bloquées (dans un sens ou dans l'autre) n'apparaissent pas.
 */
app.get('/profiles', auth, apiLimiter, wrap(async (req, res) => {
  const q = clean(req.query.q, 50).toLowerCase();
  const limit = Math.min(Math.max(Number(req.query.limit) || 50, 1), 100);
  const offset = Math.max(Number(req.query.offset) || 0, 0);

  const params = [req.uid];
  const where = [
    'users.id <> $1',
    "users.first_name <> ''",
    'users.discoverable',
    `not exists (
       select 1 from blocks b
       where (b.user_id = $1 and b.blocked_id = users.id)
          or (b.user_id = users.id and b.blocked_id = $1)
     )`,
  ];
  if (q) {
    params.push(`${q}%`);
    where.push(`lower(users.first_name) like $${params.length}`);
  }
  const filter = where.join(' and ');

  const counted = await pool.query(
    `select count(*)::int as n from users where ${filter}`,
    params,
  );
  const total = counted.rows[0].n;

  params.push(limit, offset);
  const { rows } = await pool.query(
    `select users.id, users.first_name, users.faculty, users.promotion
     from users
     where ${filter}
     order by users.first_name, users.id
     limit $${params.length - 1} offset $${params.length}`,
    params,
  );

  const nextOffset = offset + rows.length;
  res.json({
    items: rows,
    total,
    next_offset: nextOffset < total ? nextOffset : null,
  });
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

// ───────────── Blocage et signalement ─────────────
// Ces deux gestes existent pour une raison simple : une app qui met des gens
// en relation doit permettre de dire « plus jamais celui-là ».

/** Les personnes que j'ai bloquées (l'app s'en sert pour l'état des boutons). */
app.get('/blocks', auth, apiLimiter, wrap(async (req, res) => {
  const { rows } = await pool.query(
    `select u.id, u.first_name, u.faculty, b.created_at
     from blocks b
     join users u on u.id = b.blocked_id
     where b.user_id = $1
     order by b.created_at desc`,
    [req.uid],
  );
  res.json(rows);
}));

/**
 * Bloquer quelqu'un.
 *
 * Effets, dans cet ordre : la personne disparaît de mon annuaire et du sien,
 * nos choix mutuels sont effacés, et nos alarmes passées sont supprimées.
 * Aucune alarme ne pourra plus sonner entre nous, même après déblocage
 * (le choix de l'autre a été effacé, il devra le refaire).
 */
app.post('/blocks/:id', auth, apiLimiter, wrap(async (req, res) => {
  const target = validTarget(req, res);
  if (!target) return;

  try {
    await pool.query(
      `insert into blocks (user_id, blocked_id) values ($1, $2)
       on conflict do nothing`,
      [req.uid, target],
    );
  } catch (e) {
    if (e.code === '23503') return res.status(404).json({ error: 'Profil introuvable.' });
    throw e;
  }

  await pool.query(
    `delete from crushes
     where (from_user = $1 and to_user = $2) or (from_user = $2 and to_user = $1)`,
    [req.uid, target],
  );
  await pool.query(
    `delete from alarms
     where user_a = least($1::uuid, $2::uuid) and user_b = greatest($1::uuid, $2::uuid)`,
    [req.uid, target],
  );

  res.json({ blocked: true });
}));

app.delete('/blocks/:id', auth, apiLimiter, wrap(async (req, res) => {
  const target = validTarget(req, res);
  if (!target) return;
  await pool.query(
    'delete from blocks where user_id = $1 and blocked_id = $2',
    [req.uid, target],
  );
  res.json({ blocked: false });
}));

const REPORT_REASONS = new Set([
  'harcelement',
  'faux_profil',
  'intimidation',
  'autre',
]);

/**
 * Signaler quelqu'un. On enregistre le fait et le motif ; aucune décision
 * automatique n'est prise. Une seule ligne par paire : signaler deux fois met
 * à jour le motif et la date au lieu d'empiler les doublons.
 */
app.post('/reports/:id', auth, apiLimiter, wrap(async (req, res) => {
  const target = validTarget(req, res);
  if (!target) return;

  const reason = clean(req.body.reason, 40);
  if (!REPORT_REASONS.has(reason)) {
    return res.status(400).json({ error: 'Motif de signalement inconnu.' });
  }
  const details = clean(req.body.details, 500) || null;

  try {
    await pool.query(
      `insert into reports (reporter_id, reported_id, reason, details)
       values ($1, $2, $3, $4)
       on conflict (reporter_id, reported_id) do update
         set reason = excluded.reason,
             details = excluded.details,
             updated_at = now()`,
      [req.uid, target, reason, details],
    );
  } catch (e) {
    if (e.code === '23503') return res.status(404).json({ error: 'Profil introuvable.' });
    throw e;
  }
  res.json({ ok: true });
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
     where (a.user_a = $1 or a.user_b = $1)
       and not exists (
         select 1 from blocks b
         where (b.user_id = $1 and b.blocked_id = u.id)
            or (b.user_id = u.id and b.blocked_id = $1)
       )
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
