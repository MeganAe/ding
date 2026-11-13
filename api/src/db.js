import pg from 'pg';

const useSsl = process.env.DATABASE_SSL !== 'false';

export const pool = new pg.Pool({
  connectionString: process.env.DATABASE_URL,
  ssl: useSsl ? { rejectUnauthorized: false } : false,
  max: 5,
});

const SCHEMA = `
create table if not exists users (
  id uuid primary key default gen_random_uuid(),
  email text not null unique,
  password_hash text not null,
  first_name text not null default '',
  faculty text,
  promotion text,
  -- false = l'utilisateur ne veut pas apparaître dans l'annuaire du campus
  discoverable boolean not null default true,
  -- failed_attempts + locked_until : anti bourrage de mot de passe ciblé
  failed_attempts int not null default 0,
  locked_until timestamptz,
  created_at timestamptz not null default now()
);

create table if not exists crushes (
  from_user uuid not null references users(id) on delete cascade,
  to_user uuid not null references users(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (from_user, to_user),
  check (from_user <> to_user)
);

create table if not exists locations (
  user_id uuid primary key references users(id) on delete cascade,
  lat double precision not null,
  lng double precision not null,
  updated_at timestamptz not null default now()
);

-- bucket = heure écoulée depuis 1970 : une seule alarme par paire et par heure
create table if not exists alarms (
  id uuid primary key default gen_random_uuid(),
  user_a uuid not null references users(id) on delete cascade,
  user_b uuid not null references users(id) on delete cascade,
  bucket bigint not null,
  created_at timestamptz not null default now(),
  unique (user_a, user_b, bucket),
  check (user_a < user_b)
);

-- Codes de réinitialisation. On ne stocke que le hachage : une fuite de la
-- base ne permet pas de réinitialiser les comptes.
create table if not exists password_resets (
  user_id uuid primary key references users(id) on delete cascade,
  code_hash text not null,
  expires_at timestamptz not null,
  attempts int not null default 0,
  created_at timestamptz not null default now()
);

-- Blocage : un blocage coupe l'annuaire, les choix et les alarmes dans les
-- deux sens. C'est un geste de sécurité, pas un réglage de confort.
create table if not exists blocks (
  user_id uuid not null references users(id) on delete cascade,
  blocked_id uuid not null references users(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (user_id, blocked_id),
  check (user_id <> blocked_id)
);

-- Signalements : on stocke le fait et le motif, sans rien décider
-- automatiquement. Une seule ligne par paire, avec le dernier motif.
create table if not exists reports (
  id uuid primary key default gen_random_uuid(),
  reporter_id uuid not null references users(id) on delete cascade,
  reported_id uuid not null references users(id) on delete cascade,
  reason text not null,
  details text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (reporter_id, reported_id),
  check (reporter_id <> reported_id)
);

-- Codes de vérification d'email. Comme les codes de réinitialisation, on ne
-- stocke que le hachage.
create table if not exists email_verifications (
  user_id uuid primary key references users(id) on delete cascade,
  code_hash text not null,
  expires_at timestamptz not null,
  attempts int not null default 0,
  created_at timestamptz not null default now()
);

-- Table de service : elle retient les migrations déjà appliquées, pour ne les
-- rejouer qu'une fois.
create table if not exists app_meta (
  key text primary key,
  value text not null
);

-- Jetons révoqués (déconnexion à distance). On ne garde que l'identifiant du
-- jeton jusqu'à son expiration : au-delà, il ne vaut plus rien de toute façon.
create table if not exists revoked_tokens (
  jti uuid primary key,
  user_id uuid not null references users(id) on delete cascade,
  expires_at timestamptz not null
);

create index if not exists blocks_blocked_idx on blocks (blocked_id);
create index if not exists reports_reported_idx on reports (reported_id);
create index if not exists revoked_tokens_expiry_idx on revoked_tokens (expires_at);
-- Recherche dans l'annuaire : on cherche par préfixe, en minuscules.
create index if not exists users_first_name_idx on users (lower(first_name));

-- Index sur les colonnes « côté faible » des relations : sans eux, supprimer
-- un compte scanne toute la table pour appliquer le on delete cascade.
-- (user_a des alarmes est déjà couvert par la contrainte unique.)
create index if not exists crushes_to_user_idx on crushes (to_user);
create index if not exists alarms_user_b_idx on alarms (user_b);
create index if not exists alarms_created_at_idx on alarms (created_at desc);
`;

// ⚠ Tout ce qui touche à une colonne ajoutée après la v0.1 doit passer par
// ALTER ci-dessous, jamais par le SCHEMA : sur une base existante, un index
// créé sur une colonne encore absente ferait échouer le démarrage.

// Colonnes ajoutées après la première mise en production : on les crée sur les
// bases existantes (create table if not exists ne le ferait pas).
const COLUMNS = `
alter table users add column if not exists discoverable boolean not null default true;
alter table users add column if not exists failed_attempts int not null default 0;
alter table users add column if not exists locked_until timestamptz;
-- Modération : « user » ou « moderator » (fixé par ADMIN_EMAILS).
alter table users add column if not exists role text not null default 'user';
-- Suspendu = ne peut plus se connecter et disparaît de l'annuaire. On ne
-- supprime pas le compte : la trace du signalement doit rester consultable.
alter table users add column if not exists banned_at timestamptz;
-- Preuve d'acceptation des CGU : la version acceptée et quand.
alter table users add column if not exists terms_version text;
alter table users add column if not exists terms_accepted_at timestamptz;
-- Traitement d'un signalement : ouvert -> ignoré ou suspendu.
alter table reports add column if not exists status text not null default 'open';
alter table reports add column if not exists resolution text;
alter table reports add column if not exists resolved_by uuid;
alter table reports add column if not exists resolved_at timestamptz;
-- Vérification d'email : nulle tant que le code n'a pas été saisi.
alter table users add column if not exists email_verified_at timestamptz;
`;

// Index créés après les colonnes : un index sur une colonne encore absente
// ferait échouer le démarrage d'une base existante.
const INDEXES = `
create index if not exists reports_status_idx on reports (status, created_at desc);
create index if not exists users_banned_idx on users (banned_at);
`;

export async function migrate() {
  await pool.query(SCHEMA);
  await pool.query(COLUMNS);
  await pool.query(INDEXES);

  // Migration « en grand-père » : les comptes créés avant l'arrivée de la
  // vérification d'email sont considérés comme vérifiés. Sans ça, déployer
  // cette version couperait l'alarme de tous les utilisateurs existants
  // jusqu'à ce qu'ils retrouvent un code dans leur boîte. Ne s'exécute qu'une
  // fois : le marqueur reste dans app_meta.
  const done = await pool.query(
    "select 1 from app_meta where key = 'email_verified_grandfather'",
  );
  if (done.rowCount === 0) {
    await pool.query(
      'update users set email_verified_at = created_at where email_verified_at is null',
    );
    await pool.query(
      "insert into app_meta (key, value) values ('email_verified_grandfather', now()::text)",
    );
  }
}

/**
 * Purge les données devenues inutiles.
 *
 * - Les positions de plus de 24 h ne servent plus à rien (checkAlarms ignore
 *   tout ce qui date de plus de 15 min) : les garder indéfiniment serait un
 *   risque inutile pour une app qui promet que la position n'est jamais exposée.
 * - Les alarmes de plus de 30 jours n'ont aucun intérêt pour l'utilisateur.
 * - Les codes de réinitialisation expirés.
 */
export async function cleanup() {
  await pool.query(
    "delete from locations where updated_at < now() - interval '24 hours'",
  );
  await pool.query(
    "delete from alarms where created_at < now() - interval '30 days'",
  );
  await pool.query('delete from password_resets where expires_at < now()');
  await pool.query('delete from revoked_tokens where expires_at < now()');
}
