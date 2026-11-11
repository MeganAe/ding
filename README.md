# Ding

> Une alarme qui sonne quand c'est réciproque.

Tu désignes en secret les personnes qui t'intriguent. Si l'une d'elles te
désigne aussi **et** que vous vous trouvez à moins de 150 m, les deux
téléphones sonnent. Sans réciprocité, rien ne se passe : l'autre ne saura
jamais que tu l'as choisi.

L'app ne révèle jamais qui t'a choisi, ni où sont les autres : le croisement
des choix se fait entièrement côté serveur.

## Sommaire

- [Comment ça marche](#comment-ça-marche)
- [Stack](#stack)
- [Démarrer en local](#démarrer-en-local)
- [Compiler un APK](#compiler-un-apk)
- [Structure du dépôt](#structure-du-dépôt)
- [Vie privée](#vie-privée)
- [Limites connues](#limites-connues)
- [Feuille de route](#feuille-de-route)

## Comment ça marche

1. **Onboarding** — trois écrans pour expliquer la promesse (choix secret,
   réciprocité, proximité). L'écran de connexion et d'inscription reprend le
   même gabarit : photo pleine largeur qui se dissout dans le papier, titre et
   champs posés dessus, un seul bouton plein (voir `lib/core/widgets/`).
2. **Compte** — email + mot de passe, jeton JWT valable 30 jours et conservé
   dans le Keystore Android. Mot de passe oublié : code à 6 chiffres par email.
3. **Découvrir** — l'annuaire du campus, cherchable et paginé. Tu choisis /
   retires des personnes. Personne n'est notifié. Chaque personne a un menu
   pour la **bloquer** ou la **signaler**.
4. **Position** — quand l'app est ouverte, la position est envoyée toutes les
   2 minutes (précision haute). Elle n'est jamais renvoyée à un autre
   utilisateur, et elle est purgée au bout de 24 h.
5. **Alarme** — le serveur crée une alarme quand deux choix sont réciproques
   et que les deux positions datent de moins de 15 minutes et sont distantes
   de moins de 150 m. L'app interroge `/alarms` toutes les 20 secondes ; chaque
   nouvelle alarme ouvre l'écran rouge, qui sonne (`assets/audio/ding.wav`) et
   vibre. Plusieurs alarmes simultanées sont présentées l'une après l'autre.

## Stack

| Partie | Choix |
|---|---|
| App | Flutter (Dart ≥ 3.6), Riverpod, go_router, geolocator, audioplayers, flutter_secure_storage |
| API | Node.js 20 + Express, PostgreSQL, JWT, bcrypt |
| Emails | Resend (ou n'importe quel service HTTP) — mode « logs » si non configuré |
| Hébergement | Render (API) + Neon (base), tous deux en offre gratuite |
| CI | GitHub Actions — analyse, tests, APK, tests API sur PostgreSQL jetable |

## Démarrer en local

### 1. L'API

```bash
cd api
cp .env.example .env          # renseigne DATABASE_URL et JWT_SECRET
npm install
DATABASE_URL=postgresql://user:pass@localhost:5432/ding \
DATABASE_SSL=false \
JWT_SECRET=un-secret-local \
npm start
```

L'API démarre sur `http://localhost:3000` et crée ses tables toute seule.
Vérification : `curl http://localhost:3000/health`.

Sans `RESEND_API_KEY`, les emails (dont le code de réinitialisation) sont
écrits dans la console : pratique pour tester le parcours mot de passe oublié.

### 2. L'app

```bash
flutter pub get
bash tool/setup_android.sh      # génère android/ et applique le manifeste
flutter run --dart-define=API_URL=http://10.0.2.2:3000
```

`10.0.2.2` est l'adresse de la machine hôte vue depuis l'émulateur Android.
Sur un téléphone physique, utilise l'IP locale de ton ordinateur
(`http://192.168.x.x:3000`) **et ajoute-la** dans
`tool/android/network_security_config.xml`, puis relance le script.

> ⚠️ Sans `--dart-define=API_URL=...`, l'app affiche un message explicite au
> lieu d'échouer silencieusement (voir `lib/core/config.dart`).

### 3. Les tests

```bash
# Côté app : 31 tests (modèles, client HTTP, écrans)
flutter analyze          # doit afficher « No issues found! »
flutter test

# Côté API : 20 cas de bout en bout contre une vraie PostgreSQL
cd api
createdb ding_test
TEST_DATABASE_URL=postgres://user:pass@localhost:5432/ding_test npm test
```

Le test de l'API démarre le serveur lui-même sur le port 3100, vide la base
`ding_test` puis rejoue le parcours complet : inscription, annuaire paginé,
choix réciproques, alarme à 150 m, une alarme par heure, blocage, signalement,
révocation du jeton. C'est le filet de sécurité du SQL — il n'y en avait aucun
avant la 0.3.0.

### 4. Documentation de l'API

Voir [`api/README.md`](api/README.md) : routes, limites de débit, variables
d'environnement, déploiement Render + Neon.

## Compiler un APK

À chaque push sur `main`, la CI construit un APK et le publie dans les
artefacts du workflow `Build APK`. Le secret `API_URL` doit être défini dans
*Settings → Secrets and variables → Actions* — le build échoue volontairement
s'il manque, pour ne pas produire un APK incapable de joindre l'API.

En local :

```bash
bash tool/setup_android.sh
flutter build apk --release --dart-define=API_URL=https://ton-api.onrender.com
```

## Structure du dépôt

```
lib/
├── core/          config, thème, routeur, providers Riverpod, peintres
├── data/          client HTTP, stockage du jeton, modèles, repository
└── features/      auth, onboarding, discover, alarm, profile, home
api/src/
├── index.js       routes Express
├── db.js          schéma SQL, migrations, purge
└── mailer.js      envoi d'emails (Resend) ou journalisation
tool/
├── setup_android.sh          prépare android/ (utilisé par la CI)
└── android/                  manifeste et config réseau de référence
docs/              notes techniques (service de premier plan…)
test/              tests unitaires (modèles, client HTTP)
assets/            images, icônes, son d'alarme
logo/              déclinaisons du symbole Ding
```

## Vie privée

- La position n'est **jamais** renvoyée à un autre utilisateur ; elle sert
  uniquement au calcul de distance côté serveur, puis elle est purgée après
  24 h.
- Aucune route ne révèle qui t'a choisi.
- Un interrupteur « Apparaître dans l'annuaire » permet de disparaître de
  l'annuaire sans supprimer son compte.
- La suppression du compte efface tout (choix, alarmes, position) et demande
  le mot de passe.

## Limites connues

- **Arrière-plan partiel.** Depuis la 0.3.1, un service de premier plan suit
  la position : l'alarme sonne écran éteint et app en arrière-plan. Elle ne
  sonne pas si l'app est **quittée** (Android détruit alors le service). La
  suite — isolate séparé ou push FCM — est décrite dans
  [`docs/alarme-en-arriere-plan.md`](docs/alarme-en-arriere-plan.md).
- **Pas de temps réel.** Le client interroge l'API toutes les 20 s. Une alarme
  peut donc arriver jusqu'à 20 s après le croisement.
- **Une alarme par heure et par paire** (`bucket`), pour éviter le harcèlement.
- **Annuaire ouvert par défaut** : tous les inscrits visibles, sauf ceux qui
  s'en retirent. Le secret porte sur les choix, pas sur l'existence des comptes.
- **Les signalements sont enregistrés, pas encore traités.** La table
  `reports` garde le motif et la date ; aucune interface d'administration ne
  les liste. À faire avant d'ouvrir le campus au-delà d'un cercle de
  confiance.
- **Pas de vérification d'email** : rien n'empêche de s'inscrire avec l'adresse
  de quelqu'un d'autre. À traiter avant d'activer `ALLOWED_EMAIL_DOMAIN`.
- **Cold start Render** : l'API gratuite se met en veille ; le premier appel
  peut prendre plusieurs dizaines de secondes.
- **APK signé avec la clé de debug** : installable, mais refusé par le Play
  Store. Un keystore de release sera nécessaire (hors dépôt, dans les secrets).

## Feuille de route

- [x] Service de premier plan pour la position
      (l'alarme sonne écran éteint, [guide](docs/alarme-en-arriere-plan.md))
- [ ] Suivi même quand l'app est quittée (isolate séparé)
- [ ] Notification prioritaire (écran qui s'allume comme un appel)
- [ ] Notifications push FCM pour remplacer le polling 20 s
- [ ] Vérification d'email
- [x] Pagination / recherche côté serveur pour l'annuaire
- [x] Signalement et blocage d'un profil
- [ ] CGU + politique de confidentialité + âge minimum
- [ ] Polices embarquées plutôt que téléchargées par `google_fonts`
- [ ] Signature de l'APK (`key.properties` + secret GitHub)
- [x] Alarme sonore
- [x] Mot de passe oublié
- [x] Suppression de compte
- [x] Choix de visibilité dans l'annuaire

Voir [`AUDIT.md`](AUDIT.md) pour la revue technique détaillée et
[`CHANGELOG.md`](CHANGELOG.md) pour l'historique.
