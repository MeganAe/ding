/**
 * Parcours complet de l'API, contre une vraie base PostgreSQL.
 *
 *   createdb ding_test
 *   TEST_DATABASE_URL=postgres://ding:ding@127.0.0.1:5432/ding_test npm test
 *
 * Le test démarre lui-même le serveur (port TEST_PORT, 3100 par défaut) sur une
 * base vidée au préalable : il vérifie donc le SQL réel, pas une imitation.
 */
import { spawn } from 'node:child_process';
import process from 'node:process';
import { after, before, describe, test } from 'node:test';
import assert from 'node:assert/strict';
import pg from 'pg';

const DB = process.env.TEST_DATABASE_URL || 'postgres://ding:ding@127.0.0.1:5432/ding_test';
const PORT = Number(process.env.TEST_PORT || 3100);
const BASE = `http://127.0.0.1:${PORT}`;

let server;
/// Tout ce que le serveur écrit : sans RESEND_API_KEY, les emails y sont
/// recopiés, codes compris. C'est ainsi que les tests récupèrent un code.
let journal = '';

const wait = (ms) => new Promise((r) => setTimeout(r, ms));

async function health(timeoutMs = 15000) {
  const until = Date.now() + timeoutMs;
  while (Date.now() < until) {
    try {
      const res = await fetch(`${BASE}/health`);
      if (res.ok) return;
    } catch {
      // Le serveur n'écoute pas encore.
    }
    await wait(150);
  }
  throw new Error("L'API n'a pas démarré.");
}

async function api(path, { method = 'GET', token, body } = {}) {
  const res = await fetch(`${BASE}${path}`, {
    method,
    headers: {
      'Content-Type': 'application/json',
      ...(token ? { Authorization: `Bearer ${token}` } : {}),
    },
    body: body === undefined ? undefined : JSON.stringify(body),
  });
  const text = await res.text();
  return {
    status: res.status,
    data: text ? JSON.parse(text) : null,
  };
}

let n = 0;
/** Un compte neuf, unique à chaque appel (le test peut tourner plusieurs fois). */
async function account(firstName, { email: forced } = {}) {
  const email = forced ?? `test${++n}.${Date.now()}@campus.test`;
  const r = await api('/auth/signup', {
    method: 'POST',
    body: {
      email,
      password: 'motdepasse',
      first_name: firstName,
      accept_terms: true,
    },
  });
  assert.equal(r.status, 201, JSON.stringify(r.data));
  return { email, token: r.data.token, id: (await api('/me', { token: r.data.token })).data.id };
}

/// Le dernier code de vérification envoyé à cette adresse (lu dans les logs).
function codeFor(email) {
  const blocs = journal.split('EMAIL NON ENVOYÉ');
  for (let i = blocs.length - 1; i >= 0; i--) {
    if (!blocs[i].includes(email)) continue;
    const m = blocs[i].match(/code de vérification Ding est : (\d{6})/);
    if (m) return m[1];
  }
  throw new Error(`Aucun code trouvé pour ${email}`);
}

/// Un compte dont l'adresse est confirmée : indispensable pour /location.
async function verifiedAccount(firstName) {
  const a = await account(firstName);
  const r = await api('/auth/verify-email', {
    method: 'POST',
    token: a.token,
    body: { code: codeFor(a.email) },
  });
  assert.equal(r.status, 200, JSON.stringify(r.data));
  return a;
}

/// Le compte de modération : c'est ADMIN_EMAILS qui décide, pas la base.
/// Créé au premier appel, connecté ensuite (la base n'est vidée qu'une fois).
const MOD_EMAIL = 'moderateur@campus.test';
async function moderator() {
  const body = {
    email: MOD_EMAIL,
    password: 'motdepasse',
    first_name: 'Modo',
    accept_terms: true,
  };
  const signup = await api('/auth/signup', { method: 'POST', body });
  const token = signup.status === 201
    ? signup.data.token
    : (await api('/auth/login', {
        method: 'POST',
        body: { email: MOD_EMAIL, password: 'motdepasse' },
      })).data.token;
  return { email: MOD_EMAIL, token, id: (await api('/me', { token })).data.id };
}

before(async () => {
  const client = new pg.Client({ connectionString: DB });
  await client.connect();
  await client.query('drop schema public cascade; create schema public;');
  await client.end();

  server = spawn(process.execPath, ['src/index.js'], {
    cwd: new URL('..', import.meta.url).pathname,
    env: {
      ...process.env,
      DATABASE_URL: DB,
      JWT_SECRET: 'secret-de-test',
      DATABASE_SSL: 'false',
      PORT: String(PORT),
      ALARM_RADIUS_METERS: '150',
      // Les quotas de production bloqueraient un test qui crée cinquante
      // comptes en trois secondes. Ils restent actifs, juste plus larges.
      ADMIN_EMAILS: 'moderateur@campus.test',
      TERMS_VERSION: '2026-11-01',
      AUTH_RATE_LIMIT: '1000',
      API_RATE_LIMIT: '100000',
      LOCATION_RATE_LIMIT: '100000',
    },
    stdio: ['ignore', 'pipe', 'pipe'],
  });
  server.stdout.on('data', (d) => {
    journal += d.toString();
  });
  server.stderr.on('data', (d) => process.stderr.write(`[api] ${d}`));
  await health();
});

after(() => {
  server?.kill('SIGKILL');
});

describe('Configuration', () => {
  test('/config expose le rayon et les intervalles', async () => {
    const r = await api('/config');
    assert.equal(r.status, 200);
    assert.equal(r.data.alarm_radius_meters, 150);
    assert.equal(r.data.alarm_poll_seconds, 20);
  });

  test('/health vérifie la base', async () => {
    const r = await api('/health');
    assert.equal(r.status, 200);
    assert.equal(r.data.ok, true);
  });
});

describe('Comptes', () => {
  test('refuse un mot de passe trop court', async () => {
    const r = await api('/auth/signup', {
      method: 'POST',
      body: { email: 'court@campus.test', password: 'abc', first_name: 'X' },
    });
    assert.equal(r.status, 400);
  });

  test('refuse un email déjà pris', async () => {
    const a = await account('Alice');
    const r = await api('/auth/signup', {
      method: 'POST',
      body: {
        email: a.email,
        password: 'motdepasse',
        first_name: 'Clone',
        accept_terms: true,
      },
    });
    assert.equal(r.status, 409);
  });

  test('refuse un mauvais mot de passe sans dire lequel est faux', async () => {
    const a = await account('Alice');
    const r = await api('/auth/login', {
      method: 'POST',
      body: { email: a.email, password: 'pas-le-bon' },
    });
    assert.equal(r.status, 401);
    assert.match(r.data.error, /Email ou mot de passe/);
  });

  test('/me renvoie mon email, mais /profiles ne le montre jamais', async () => {
    const a = await account('Alice');
    const b = await account('Bob');

    const me = await api('/me', { token: a.token });
    assert.equal(me.data.email, a.email);

    const list = await api('/profiles', { token: a.token });
    assert.ok(list.data.items.some((p) => p.id === b.id));
    for (const p of list.data.items) assert.equal(p.email, undefined);
  });

  test('la déconnexion révoque le jeton côté serveur', async () => {
    const a = await account('Alice');
    const autre = await account('Alice');

    assert.equal((await api('/auth/logout', { method: 'POST', token: a.token })).status, 200);
    assert.equal((await api('/me', { token: a.token })).status, 401);
    // Le jeton d'une autre session n'est pas touché.
    assert.equal((await api('/me', { token: autre.token })).status, 200);
  });
});

describe('Annuaire', () => {
  test('pagine et compte', async () => {
    for (const prenom of ['Emma', 'Elias', 'Eva']) await account(prenom);
    const a = await account('Zoe');

    const page1 = await api('/profiles?limit=2', { token: a.token });
    assert.equal(page1.status, 200);
    assert.equal(page1.data.items.length, 2);
    assert.ok(page1.data.total >= 4);
    assert.equal(page1.data.next_offset, 2);

    const page2 = await api(`/profiles?limit=2&offset=${page1.data.next_offset}`, {
      token: a.token,
    });
    assert.notEqual(page2.data.items[0].id, page1.data.items[0].id);
  });

  test('cherche par début de prénom, sans tenir compte des majuscules', async () => {
    const a = await account('Zoe');
    const r = await api('/profiles?q=emm', { token: a.token });
    assert.equal(r.status, 200);
    assert.ok(r.data.items.length >= 1);
    assert.ok(r.data.items.every((p) => /^emm/i.test(p.first_name)));
  });

  test('ne montre pas son propre profil', async () => {
    const a = await account('Unique' + n);
    const r = await api(`/profiles?q=${encodeURIComponent('Unique' + n)}`, { token: a.token });
    assert.equal(r.data.total, 0);
  });
});

describe('Choix secrets et alarme', () => {
  test("l'alarme sonne quand deux choix sont réciproques et proches", async () => {
    const a = await verifiedAccount('Alice');
    const b = await verifiedAccount('Bob');

    assert.equal((await api(`/crushes/${b.id}`, { method: 'POST', token: a.token })).status, 200);
    assert.equal((await api(`/crushes/${a.id}`, { method: 'POST', token: b.token })).status, 200);

    // Deux points à ~20 m l'un de l'autre, à Bukavu.
    await api('/location', { method: 'POST', token: a.token, body: { lat: -2.5083, lng: 28.8608 } });
    await api('/location', { method: 'POST', token: b.token, body: { lat: -2.5085, lng: 28.8610 } });

    const alarms = await api('/alarms', { token: a.token });
    assert.equal(alarms.status, 200);
    assert.equal(alarms.data.length, 1);
    assert.equal(alarms.data[0].other_id, b.id);
    assert.equal(alarms.data[0].other_name, 'Bob');
  });

  test('aucune alarme si les choix ne sont pas réciproques', async () => {
    const a = await verifiedAccount('Alice');
    const b = await verifiedAccount('Bob');
    await api(`/crushes/${b.id}`, { method: 'POST', token: a.token });
    await api('/location', { method: 'POST', token: a.token, body: { lat: 0, lng: 0 } });
    await api('/location', { method: 'POST', token: b.token, body: { lat: 0, lng: 0.0001 } });
    assert.equal((await api('/alarms', { token: a.token })).data.length, 0);
  });

  test('aucune alarme au-delà du rayon', async () => {
    const a = await verifiedAccount('Alice');
    const b = await verifiedAccount('Bob');
    await api(`/crushes/${b.id}`, { method: 'POST', token: a.token });
    await api(`/crushes/${a.id}`, { method: 'POST', token: b.token });
    // ~1,1 km : au-delà des 150 m.
    await api('/location', { method: 'POST', token: a.token, body: { lat: 0, lng: 0 } });
    await api('/location', { method: 'POST', token: b.token, body: { lat: 0, lng: 0.01 } });
    assert.equal((await api('/alarms', { token: a.token })).data.length, 0);
  });

  test('une seule alarme par heure pour une même paire', async () => {
    const a = await verifiedAccount('Alice');
    const b = await verifiedAccount('Bob');
    await api(`/crushes/${b.id}`, { method: 'POST', token: a.token });
    await api(`/crushes/${a.id}`, { method: 'POST', token: b.token });
    await api('/location', { method: 'POST', token: a.token, body: { lat: 1, lng: 1 } });
    for (let i = 0; i < 3; i++) {
      await api('/location', { method: 'POST', token: b.token, body: { lat: 1, lng: 1.00005 } });
    }
    assert.equal((await api('/alarms', { token: a.token })).data.length, 1);
  });

  test('refuse de se choisir soi-même et les identifiants invalides', async () => {
    const a = await verifiedAccount('Alice');
    assert.equal((await api(`/crushes/${a.id}`, { method: 'POST', token: a.token })).status, 400);
    assert.equal((await api('/crushes/pas-un-uuid', { method: 'POST', token: a.token })).status, 400);
    const inconnu = '11111111-2222-3333-4444-555555555555';
    assert.equal((await api(`/crushes/${inconnu}`, { method: 'POST', token: a.token })).status, 404);
  });
});

describe('Blocage et signalement', () => {
  test('bloquer retire la personne de l’annuaire, des deux côtés', async () => {
    const a = await account('Alice');
    const b = await account('Bob');

    assert.equal((await api(`/blocks/${b.id}`, { method: 'POST', token: a.token })).status, 200);
    const vuParA = await api('/profiles', { token: a.token });
    assert.ok(!vuParA.data.items.some((p) => p.id === b.id));
    const vuParB = await api('/profiles', { token: b.token });
    assert.ok(!vuParB.data.items.some((p) => p.id === a.id));
    const bloques = (await api('/blocks', { token: a.token })).data;
    assert.deepEqual(bloques.map((x) => x.id), [b.id]);
    assert.equal(bloques[0].first_name, 'Bob');
  });

  test('bloquer efface les choix et les alarmes de la paire', async () => {
    const a = await verifiedAccount('Alice');
    const b = await verifiedAccount('Bob');
    await api(`/crushes/${b.id}`, { method: 'POST', token: a.token });
    await api(`/crushes/${a.id}`, { method: 'POST', token: b.token });
    await api('/location', { method: 'POST', token: a.token, body: { lat: 2, lng: 2 } });
    await api('/location', { method: 'POST', token: b.token, body: { lat: 2, lng: 2.00001 } });
    assert.equal((await api('/alarms', { token: a.token })).data.length, 1);

    await api(`/blocks/${b.id}`, { method: 'POST', token: a.token });

    assert.equal((await api('/alarms', { token: a.token })).data.length, 0);
    assert.equal((await api('/alarms', { token: b.token })).data.length, 0);
    assert.deepEqual((await api('/crushes', { token: a.token })).data, []);
    assert.deepEqual((await api('/crushes', { token: b.token })).data, []);
  });

  test('un blocage empêche une nouvelle alarme même si les deux re-choisissent', async () => {
    const a = await account('Alice');
    const b = await account('Bob');
    await api(`/blocks/${b.id}`, { method: 'POST', token: a.token });
    // L'annuaire les cache, mais un identifiant connu peut être rejoué.
    await api(`/crushes/${b.id}`, { method: 'POST', token: a.token });
    await api(`/crushes/${a.id}`, { method: 'POST', token: b.token });
    await api('/location', { method: 'POST', token: a.token, body: { lat: 3, lng: 3 } });
    await api('/location', { method: 'POST', token: b.token, body: { lat: 3, lng: 3.00001 } });
    assert.equal((await api('/alarms', { token: a.token })).data.length, 0);
  });

  test('débloquer remet la personne dans l’annuaire', async () => {
    const a = await account('Alice');
    const b = await account('Bob');
    await api(`/blocks/${b.id}`, { method: 'POST', token: a.token });
    await api(`/blocks/${b.id}`, { method: 'DELETE', token: a.token });
    const r = await api('/profiles', { token: a.token });
    assert.ok(r.data.items.some((p) => p.id === b.id));
  });

  test('signaler accepte un motif connu et refuse les autres', async () => {
    const a = await account('Alice');
    const b = await account('Bob');

    const ok = await api(`/reports/${b.id}`, {
      method: 'POST',
      token: a.token,
      body: { reason: 'harcelement', details: 'messages insistants' },
    });
    assert.equal(ok.status, 200);

    const deuxFois = await api(`/reports/${b.id}`, {
      method: 'POST',
      token: a.token,
      body: { reason: 'faux_profil' },
    });
    assert.equal(deuxFois.status, 200, 'un second signalement met à jour, sans erreur');

    const non = await api(`/reports/${b.id}`, {
      method: 'POST',
      token: a.token,
      body: { reason: 'je-n-aime-pas' },
    });
    assert.equal(non.status, 400);
  });
});

describe('CGU', () => {
  test('refuse une inscription sans acceptation, avec un code exploitable', async () => {
    const r = await api('/auth/signup', {
      method: 'POST',
      body: {
        email: `sanscgu${Date.now()}@campus.test`,
        password: 'motdepasse',
        first_name: 'Sans',
      },
    });
    assert.equal(r.status, 400);
    assert.equal(r.data.code, 'terms_required');
    assert.equal(r.data.terms_version, '2026-11-01');
  });

  test('/me garde la trace de la version acceptée', async () => {
    const a = await account('Léa');
    const me = await api('/me', { token: a.token });
    assert.equal(me.data.terms_version, '2026-11-01');
    assert.ok(me.data.terms_accepted_at);
    assert.equal(me.data.role, 'user');
  });

  test('/config publie la version en cours, sans authentification', async () => {
    const r = await api('/config');
    assert.equal(r.data.terms_version, '2026-11-01');
  });
});

describe('Modération des signalements', () => {
  test('un compte ordinaire ne voit pas la file de signalements', async () => {
    const a = await account('Curieux');
    const file = await api('/admin/reports', { token: a.token });
    assert.equal(file.status, 403);

    const essai = await api(`/admin/reports/${a.id}/resolve`, {
      method: 'POST',
      token: a.token,
      body: { action: 'ban' },
    });
    assert.equal(essai.status, 403, 'aucune auto-suspension possible');
  });

  test('la file regroupe par personne signalée et n’identifie pas le signalant', async () => {
    const modo = await moderator();
    const cible = await account('Cible');
    const a = await account('Temoin1');
    const b = await account('Temoin2');

    for (const [qui, reason] of [[a, 'harcelement'], [b, 'harcelement']]) {
      const r = await api(`/reports/${cible.id}`, {
        method: 'POST',
        token: qui.token,
        body: { reason, details: 'insistant' },
      });
      assert.equal(r.status, 200);
    }

    const file = await api('/admin/reports', { token: modo.token });
    assert.equal(file.status, 200);
    const ligne = file.data.items.find((i) => i.id === cible.id);
    assert.ok(ligne, 'la personne signalée apparaît');
    assert.equal(ligne.reports, 2, 'deux signalements regroupés');
    assert.equal(ligne.first_name, 'Cible');
    assert.equal(ligne.banned, false);

    const brut = JSON.stringify(file.data);
    assert.ok(!brut.includes(a.id), 'l’identifiant du signalant reste secret');
    assert.ok(!brut.includes(b.id), 'l’identifiant du signalant reste secret');
    assert.ok(!brut.includes(a.email), 'aucun email ne fuit');
  });

  test('ignorer un signalement le referme et laisse le compte actif', async () => {
    const modo = await moderator();
    const cible = await account('Innocent');
    const a = await account('Temoin');

    await api(`/reports/${cible.id}`, {
      method: 'POST',
      token: a.token,
      body: { reason: 'autre' },
    });

    const r = await api(`/admin/reports/${cible.id}/resolve`, {
      method: 'POST',
      token: modo.token,
      body: { action: 'dismiss', note: 'photographies de profil, rien de répréhensible' },
    });
    assert.equal(r.status, 200);
    assert.equal(r.data.status, 'dismissed');

    const file = await api('/admin/reports', { token: modo.token });
    assert.ok(!file.data.items.some((i) => i.id === cible.id), 'sortie de la file');

    // Le compte fonctionne toujours.
    const login = await api('/auth/login', {
      method: 'POST',
      body: { email: cible.email, password: 'motdepasse' },
    });
    assert.equal(login.status, 200);

    // Et on ne peut pas refermer deux fois.
    const encore = await api(`/admin/reports/${cible.id}/resolve`, {
      method: 'POST',
      token: modo.token,
      body: { action: 'dismiss' },
    });
    assert.equal(encore.status, 404);
  });

  test('suspendre un compte le coupe partout : connexion, annuaire, alarmes', async () => {
    const modo = await moderator();
    const cible = await account('Suspendu');
    const a = await account('Temoin');

    await api(`/reports/${cible.id}`, {
      method: 'POST',
      token: a.token,
      body: { reason: 'harcelement', details: 'insultes en messages' },
    });

    const r = await api(`/admin/reports/${cible.id}/resolve`, {
      method: 'POST',
      token: modo.token,
      body: { action: 'ban' },
    });
    assert.equal(r.status, 200);
    assert.equal(r.data.status, 'banned');

    const login = await api('/auth/login', {
      method: 'POST',
      body: { email: cible.email, password: 'motdepasse' },
    });
    assert.equal(login.status, 403, 'connexion refusée');

    const jeton = await api('/crushes', { token: cible.token });
    assert.equal(jeton.status, 401, 'le jeton existant ne vaut plus rien');

    const annuaire = await api('/profiles?limit=100', { token: a.token });
    assert.ok(!annuaire.data.items.some((p) => p.id === cible.id), 'disparaît de l’annuaire');

    const file = await api('/admin/reports?status=all', { token: modo.token });
    const ligne = file.data.items.find((i) => i.id === cible.id);
    assert.equal(ligne.banned, true);
    assert.equal(ligne.open_reports, 0);

    // Un compte suspendu ne peut pas être re-suspendu : la file est vide.
    const encore = await api(`/admin/reports/${cible.id}/resolve`, {
      method: 'POST',
      token: modo.token,
      body: { action: 'ban' },
    });
    assert.equal(encore.status, 404);
  });

  test('refuse une action inconnue et un identifiant mal formé', async () => {
    const modo = await moderator();
    const cible = await account('Peu importe');
    await api(`/reports/${cible.id}`, {
      method: 'POST',
      token: (await account('Temoin')).token,
      body: { reason: 'autre' },
    });

    const action = await api(`/admin/reports/${cible.id}/resolve`, {
      method: 'POST',
      token: modo.token,
      body: { action: 'supprimer-tout' },
    });
    assert.equal(action.status, 400);

    const id = await api('/admin/reports/pas-un-uuid/resolve', {
      method: 'POST',
      token: modo.token,
      body: { action: 'dismiss' },
    });
    assert.equal(id.status, 400);
  });
});

describe('Vérification de l’adresse email', () => {
  test('sans confirmation, l’alarme ne peut pas sonner', async () => {
    const a = await account('NonVerifie');
    const r = await api('/location', {
      method: 'POST',
      token: a.token,
      body: { lat: 0, lng: 0 },
    });
    assert.equal(r.status, 403);
    assert.equal(r.data.code, 'email_not_verified');

    const me = await api('/me', { token: a.token });
    assert.equal(me.data.email_verified, false);
  });

  test('un mauvais code est refusé, et cinq essais épuisent le code', async () => {
    const a = await account('Maladroit');
    const faux = await api('/auth/verify-email', {
      method: 'POST',
      token: a.token,
      body: { code: '000000' },
    });
    assert.equal(faux.status, 400);

    for (let i = 0; i < 4; i++) {
      await api('/auth/verify-email', {
        method: 'POST',
        token: a.token,
        body: { code: '000000' },
      });
    }
    // Même le bon code ne passe plus : il faut en demander un autre.
    const bon = await api('/auth/verify-email', {
      method: 'POST',
      token: a.token,
      body: { code: codeFor(a.email) },
    });
    assert.equal(bon.status, 400);
    assert.match(bon.data.error, /Demande-en un nouveau/);

    // …mais pas tout de suite (une minute d'attente entre deux envois).
    const trop = await api('/auth/verify-email/resend', {
      method: 'POST',
      token: a.token,
    });
    assert.equal(trop.status, 429);
  });

  test('le bon code confirme l’adresse et débloque la position', async () => {
    const a = await account('Serieux');
    const r = await api('/auth/verify-email', {
      method: 'POST',
      token: a.token,
      body: { code: codeFor(a.email) },
    });
    assert.equal(r.status, 200);

    const me = await api('/me', { token: a.token });
    assert.equal(me.data.email_verified, true);

    const loc = await api('/location', {
      method: 'POST',
      token: a.token,
      body: { lat: 1, lng: 1 },
    });
    assert.equal(loc.status, 200);

    // Vérifier deux fois ne casse rien : l'app peut réémettre la requête.
    const encore = await api('/auth/verify-email', {
      method: 'POST',
      token: a.token,
      body: { code: '123456' },
    });
    assert.equal(encore.status, 200);
    assert.equal(encore.data.already, true);
  });

  test('un code mal formé est refusé sans consommer d’essai', async () => {
    const a = await account('Distrait');
    const r = await api('/auth/verify-email', {
      method: 'POST',
      token: a.token,
      body: { code: '12' },
    });
    assert.equal(r.status, 400);
    assert.match(r.data.error, /six chiffres/);
  });
});

describe('Réactivation après suspension', () => {
  test('restaurer un compte suspendu lui rend l’accès', async () => {
    const modo = await moderator();
    const cible = await account('Repenti');
    const a = await account('Temoin');
    await api(`/reports/${cible.id}`, {
      method: 'POST',
      token: a.token,
      body: { reason: 'harcelement' },
    });
    await api(`/admin/reports/${cible.id}/resolve`, {
      method: 'POST',
      token: modo.token,
      body: { action: 'ban' },
    });
    assert.equal(
      (await api('/auth/login', {
        method: 'POST',
        body: { email: cible.email, password: 'motdepasse' },
      })).status,
      403,
    );

    const restore = await api(`/admin/users/${cible.id}/restore`, {
      method: 'POST',
      token: modo.token,
    });
    assert.equal(restore.status, 200);

    const login = await api('/auth/login', {
      method: 'POST',
      body: { email: cible.email, password: 'motdepasse' },
    });
    assert.equal(login.status, 200, 'le compte revit');

    // Restaurer deux fois n'a pas de sens, et le dit.
    const encore = await api(`/admin/users/${cible.id}/restore`, {
      method: 'POST',
      token: modo.token,
    });
    assert.equal(encore.status, 404);
  });

  test('un compte ordinaire ne peut pas restaurer un compte', async () => {
    const a = await account('Malin');
    const r = await api(`/admin/users/${a.id}/restore`, {
      method: 'POST',
      token: a.token,
    });
    assert.equal(r.status, 403);
  });
});
