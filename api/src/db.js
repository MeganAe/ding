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
`;

export async function migrate() {
  await pool.query(SCHEMA);
}
