import { randomInt, randomUUID } from 'node:crypto';
import express from 'express';
import rateLimit from 'express-rate-limit';
import bcrypt from 'bcryptjs';
import jwt from 'jsonwebtoken';
import { pool, migrate, cleanup } from './db.js';
import { sendMail, resetCodeEmail, verificationEmail, reportNoticeEmail } from './mailer.js';

const PORT = process.env.PORT || 3000;
const JWT_SECRET = process.env.JWT_SECRET;
const RADIUS = Number(process.env.ALARM_RADIUS_METERS || 150);
const alarmPollSeconds = Number(process.env.ALARM_POLL_SECONDS || 20);
const locationIntervalSeconds = Number(process.env.LOCATION_INTERVAL_SECONDS || 120);
const DOMAIN = (process.env.ALLOWED_EMAIL_DOMAIN || '').trim().toLowerCase();
// Version des conditions d'utilisation. À changer quand le texte change :
// l'app peut alors redemander l'acceptation (voir GET /config).
const TERMS_VERSION = (process.env.TERMS_VERSION || '2026-11-01').trim();
// Les modérateurs sont désignés par leur email, pas par un écran d'admin :
// pas de rôle à s'attribuer soi-même, il faut modifier la configuration.
const ADMIN_EMAILS = new Set(
  (process.env.ADMIN_EMAILS || '')
    .split(',')
    .map((e) => e.trim().toLowerCase())
    .filter(Boolean),
);

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

  // Un compte suspendu perd l'accès immédiatement. On répond 401 (et non 403)
  // pour que l'app efface le jeton et ramène à l'écran de connexion : sinon
  // elle resterait bloquée sur des erreurs sans issue.
  try {
    const { rows } = await pool.query(
      'select role, banned_at, email_verified_at from users where id = $1',
      [payload.sub],
    );
    const me = rows[0];
    if (!me) return res.status(401).json({ error: 'Compte introuvable.' });
    if (me.banned_at) {
      return res.status(401).json({
        error: 'Ce compte a été suspendu. Écris à l’équipe si tu penses qu’il s’agit d’une erreur.',
      });
    }
    req.role = me.role === 'moderator' ? 'moderator' : 'user';
    req.verified = me.email_verified_at !== null;
  } catch (e) {
    return next(e);
  }

  req.uid = payload.sub;
  req.jti = payload.jti ?? null;
  req.tokenExp = payload.exp ?? null;
  next();
}

// ───────────── Vérification d'email ─────────────
// Un code à 6 chiffres plutôt qu'un lien : l'app n'a pas de liens profonds, et
// un code se recopie sans dépendre d'un domaine vérifié. Même choix que pour
// la réinitialisation de mot de passe.
const VERIFY_TTL_HOURS = 24;
const MAX_VERIFY_ATTEMPTS = 5;
const VERIFY_RESEND_SECONDS = 60;

/// Tire un code, l'enregistre haché, et l'envoie. Ne lève jamais : un email
/// qui ne part pas ne doit pas faire échouer une inscription.
async function issueEmailCode(userId, email) {
  const code = String(randomInt(0, 1000000)).padStart(6, '0');
  const hash = await bcrypt.hash(code, 10);
  await pool.query(
    `insert into email_verifications (user_id, code_hash, expires_at, attempts)
     values ($1, $2, now() + make_interval(hours => $3), 0)
     on conflict (user_id) do update
       set code_hash = excluded.code_hash,
           expires_at = excluded.expires_at,
           attempts = 0,
           created_at = now()`,
    [userId, hash, VERIFY_TTL_HOURS],
  );
  const { subject, text } = verificationEmail(code);
  await sendMail({ to: email, subject, text });
  return code;
}

/// Réservé à l'équipe de modération (emails listés dans ADMIN_EMAILS).
function moderator(req, res, next) {
  if (req.role !== 'moderator') {
    return res.status(403).json({ error: 'Réservé à l’équipe de modération.' });
  }
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
    terms_version: TERMS_VERSION,
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
  // Accepter les CGU n'est pas une case décorative : on refuse la création du
  // compte sans elle, sinon la preuve d'acceptation ne vaut rien.
  if (req.body.accept_terms !== true) {
    return res.status(400).json({
      error: 'Tu dois accepter les conditions d’utilisation pour créer un compte.',
      code: 'terms_required',
      terms_version: TERMS_VERSION,
    });
  }
  if (DOMAIN && !email.endsWith(`@${DOMAIN}`)) {
    return res.status(400).json({ error: `Utilise ton adresse @${DOMAIN}.` });
  }

  const hash = await bcrypt.hash(password, 10);
  try {
    const role = ADMIN_EMAILS.has(email) ? 'moderator' : 'user';
    const { rows } = await pool.query(
      `insert into users (email, password_hash, first_name, role, terms_version, terms_accepted_at)
       values ($1, $2, $3, $4, $5, now()) returning id`,
      [email, hash, firstName, role, TERMS_VERSION],
    );
    // Le compte existe et se connecte, mais l'alarme reste muette tant que
    // l'adresse n'est pas confirmée (voir POST /location).
    await issueEmailCode(rows[0].id, email);
    res.status(201).json({ token: sign(rows[0].id), email_verified: false });
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
    `select id, password_hash, failed_attempts, locked_until, banned_at
     from users where email = $1`,
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

  // Compte suspendu : le mot de passe est bon, mais l'accès reste fermé.
  if (user.banned_at) {
    return res.status(403).json({
      error: 'Ce compte a été suspendu. Écris à l’équipe si tu penses qu’il s’agit d’une erreur.',
    });
  }

  if (user.failed_attempts > 0 || user.locked_until) {
    await pool
      .query(
        'update users set failed_attempts = 0, locked_until = null where id = $1',
        [user.id],
      )
      .catch(() => {});
  }

  // Promotion par configuration : un email ajouté à ADMIN_EMAILS devient
  // modérateur à sa prochaine connexion, sans migration de données.
  const role = ADMIN_EMAILS.has(email) ? 'moderator' : 'user';
  await pool
    .query(
      `update users set role = $2 where id = $1 and role <> $2`,
      [user.id, role],
    )
    .catch(() => {});

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
    `select pr.code_hash, pr.expires_at, pr.attempts, u.id as user_id,
            u.banned_at
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

  // Un compte suspendu ne retrouve pas l'accès en réinitialisant son mot de
  // passe : sinon la suspension ne tiendrait qu'à un clic.
  if (row.banned_at) {
    return res.status(403).json({
      error: 'Ce compte a été suspendu. Écris à l’équipe si tu penses qu’il s’agit d’une erreur.',
    });
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
// Ré-acceptation après un changement de texte : l'app compare la version
// qu'elle connaît (GET /config) à celle enregistrée sur le compte (/me), et
// appelle cette route quand elles diffèrent.
app.post('/auth/accept-terms', auth, apiLimiter, wrap(async (req, res) => {
  await pool.query(
    'update users set terms_version = $2, terms_accepted_at = now() where id = $1',
    [req.uid, TERMS_VERSION],
  );
  res.json({ ok: true, terms_version: TERMS_VERSION });
}));

app.post('/auth/verify-email', auth, authLimiter, wrap(async (req, res) => {
  const code = clean(req.body.code, 10);
  if (!/^\d{6}$/.test(code)) {
    return res.status(400).json({ error: 'Le code fait six chiffres.' });
  }
  if (req.verified) return res.json({ ok: true, already: true });

  const { rows } = await pool.query(
    'select code_hash, expires_at, attempts from email_verifications where user_id = $1',
    [req.uid],
  );
  const row = rows[0];
  const expire = row && new Date(row.expires_at) < new Date();
  if (!row || expire || row.attempts >= MAX_VERIFY_ATTEMPTS) {
    return res.status(400).json({
      error: 'Code invalide ou expiré. Demande-en un nouveau.',
      code: 'invalid_code',
    });
  }
  if (!(await bcrypt.compare(code, row.code_hash))) {
    await pool.query(
      'update email_verifications set attempts = attempts + 1 where user_id = $1',
      [req.uid],
    );
    return res.status(400).json({
      error: 'Ce code ne correspond pas.',
      code: 'invalid_code',
    });
  }

  await pool.query('update users set email_verified_at = now() where id = $1', [req.uid]);
  await pool.query('delete from email_verifications where user_id = $1', [req.uid]);
  res.json({ ok: true });
}));

app.post('/auth/verify-email/resend', auth, authLimiter, wrap(async (req, res) => {
  if (req.verified) return res.json({ ok: true, already: true });

  // Pas plus d'un envoi par minute : sans ça, la route devient un moyen
  // d'inonder une boîte aux lettres, ou la nôtre.
  const { rows } = await pool.query(
    `select extract(epoch from (now() - created_at))::int as age
     from email_verifications where user_id = $1`,
    [req.uid],
  );
  if (rows[0] && rows[0].age < VERIFY_RESEND_SECONDS) {
    return res.status(429).json({
      error: `Attends ${VERIFY_RESEND_SECONDS - rows[0].age} secondes avant de redemander un code.`,
    });
  }

  const me = await pool.query('select email from users where id = $1', [req.uid]);
  if (me.rowCount === 0) return res.status(404).json({ error: 'Compte introuvable.' });
  await issueEmailCode(req.uid, me.rows[0].email);
  res.json({ ok: true });
}));

const PRIVATE_FIELDS =
    'id, email, first_name, faculty, promotion, discoverable, role, terms_version, terms_accepted_at';

app.get('/me', auth, apiLimiter, wrap(async (req, res) => {
  const { rows } = await pool.query(
    `select ${PRIVATE_FIELDS},
            (email_verified_at is not null) as email_verified
     from users where id = $1`,
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
    'users.banned_at is null',
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

  let nouveau = false;
  try {
    const { rows } = await pool.query(
      `insert into reports (reporter_id, reported_id, reason, details)
       values ($1, $2, $3, $4)
       on conflict (reporter_id, reported_id) do update
         set reason = excluded.reason,
             details = excluded.details,
             updated_at = now()
       returning (xmax = 0) as nouveau`,
      [req.uid, target, reason, details],
    );
    nouveau = rows[0]?.nouveau === true;
  } catch (e) {
    if (e.code === '23503') return res.status(404).json({ error: 'Profil introuvable.' });
    throw e;
  }

  // On prévient l'équipe une seule fois par personne signalée : resignaler ne
  // doit pas noyer la boîte de réception. L'envoi ne bloque jamais la réponse.
  if (nouveau) notifyModerators(target).catch(() => {});
  res.json({ ok: true });
}));

// ───────────── Modération des signalements ─────────────
// Le signalement n'est pas une décision : il ouvre une ligne dans la file.
// Un modérateur la referme en ignorant ou en suspendant le compte.
//
// Deux principes tenus par le SQL ci-dessous :
//  - le signalant n'est jamais identifié, même à l'équipe (pas de vengeance
//    possible dans un campus de quelques centaines de personnes) ;
//  - on renvoie un profil par personne signalée, avec le nombre de
//    signalements : un seul avis isolé et vingt avis concordants ne se
//    traitent pas de la même façon.
const RESOLUTIONS = new Set(['dismiss', 'ban']);

/// Prévient l'équipe qu'un profil vient d'être signalé.
/// On n'y met ni l'identité du signalant, ni sa position, ni son email.
async function notifyModerators(reportedId) {
  const destinataires = new Set(ADMIN_EMAILS);
  const { rows: mods } = await pool.query(
    "select email from users where role = 'moderator'",
  );
  for (const m of mods) destinataires.add(m.email);
  if (destinataires.size === 0) return;

  const { rows } = await pool.query(
    `select coalesce(u.first_name, '') as first_name,
            count(r.id)::int as reports,
            string_agg(distinct r.reason, ', ') as reasons
     from users u left join reports r on r.reported_id = u.id
     where u.id = $1
     group by u.first_name`,
    [reportedId],
  );
  const info = rows[0];
  if (!info) return;

  const { subject, text } = reportNoticeEmail({
    name: info.first_name,
    reports: info.reports,
    reasons: info.reasons ?? 'non précisé',
  });
  for (const to of destinataires) await sendMail({ to, subject, text });
}

app.get('/admin/reports', auth, moderator, apiLimiter, wrap(async (req, res) => {
  const onlyOpen = req.query.status !== 'all';
  const limit = Math.min(Math.max(Number(req.query.limit) || 50, 1), 100);
  const offset = Math.max(Number(req.query.offset) || 0, 0);

  const filtre = onlyOpen ? "where r.status = 'open'" : '';

  const { rows } = await pool.query(
    `select r.reported_id as id,
            u.first_name,
            u.faculty,
            (u.banned_at is not null) as banned,
            count(*)::int as reports,
            count(*) filter (where r.status = 'open')::int as open_reports,
            max(r.created_at) as last_report_at,
            array_agg(distinct r.reason) as reasons,
            (array_agg(r.reason order by r.created_at desc))[1] as last_reason,
            (array_agg(r.details order by r.created_at desc))[1] as last_details
     from reports r
     join users u on u.id = r.reported_id
     ${filtre}
     group by r.reported_id, u.first_name, u.faculty, u.banned_at
     order by open_reports desc, max(r.created_at) desc
     limit $1 offset $2`,
    [limit, offset],
  );

  const counts = await pool.query(
    `select
       (select count(distinct reported_id) from reports
         where status = 'open')::int as total,
       (select count(*) from reports where status = 'open')::int as open_reports`,
  );

  res.json({
    items: rows,
    total: counts.rows[0].total,
    open_reports: counts.rows[0].open_reports,
  });
}));

// Réactivation : une suspension ne se lève que par un geste explicite de
// l'équipe — jamais automatiquement, jamais depuis le compte concerné.
app.post('/admin/users/:id/restore', auth, moderator, apiLimiter, wrap(async (req, res) => {
  const target = String(req.params.id || '');
  if (!UUID_RE.test(target)) {
    return res.status(400).json({ error: 'Identifiant de profil invalide.' });
  }
  const { rowCount } = await pool.query(
    'update users set banned_at = null where id = $1 and banned_at is not null',
    [target],
  );
  if (rowCount === 0) {
    return res.status(404).json({ error: 'Ce compte n’est pas suspendu.' });
  }
  res.json({ ok: true });
}));

app.post('/admin/reports/:id/resolve', auth, moderator, apiLimiter, wrap(async (req, res) => {
  const target = String(req.params.id || '');
  if (!UUID_RE.test(target)) {
    return res.status(400).json({ error: 'Identifiant de profil invalide.' });
  }
  if (target === req.uid) {
    return res.status(400).json({ error: 'Tu ne peux pas te modérer toi-même.' });
  }

  const action = clean(req.body.action, 20);
  if (!RESOLUTIONS.has(action)) {
    return res.status(400).json({ error: 'Action inconnue (dismiss ou ban).' });
  }
  const note = clean(req.body.note, 300) || null;
  const status = action === 'ban' ? 'banned' : 'dismissed';

  const resolved = await pool.query(
    `update reports
        set status = $2, resolution = $3, resolved_by = $4, resolved_at = now()
      where reported_id = $1 and status = 'open'`,
    [target, status, note, req.uid],
  );
  if (resolved.rowCount === 0) {
    return res.status(404).json({ error: 'Aucun signalement ouvert pour ce profil.' });
  }

  if (action === 'ban') {
    // Date de suspension + coupure immédiate : plus de position, plus de
    // choix secrets. Sans ça, une alarme pourrait encore sonner avec
    // quelqu'un qui n'a plus accès à l'app.
    await pool.query(
      'update users set banned_at = now() where id = $1 and banned_at is null',
      [target],
    );
    await pool.query('delete from locations where user_id = $1', [target]);
    await pool.query(
      'delete from crushes where from_user = $1 or to_user = $1',
      [target],
    );
  }

  res.json({ ok: true, status, resolved: resolved.rowCount });
}));

// ───────────── Position (jamais exposée) ─────────────
app.post('/location', auth, locationLimiter, wrap(async (req, res) => {
  // L'alarme est la raison d'être de l'app : elle exige une adresse vérifiée,
  // sinon un compte jetable peut faire sonner le téléphone de quelqu'un.
  // Le reste de l'app (annuaire, choix) reste utilisable sans vérification.
  if (!req.verified) {
    return res.status(403).json({
      error: 'Confirme ton adresse email pour que l’alarme puisse sonner.',
      code: 'email_not_verified',
    });
  }

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
