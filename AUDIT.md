# Audit technique — Ding

> Revue du dépôt [MeganAe/ding](https://github.com/MeganAe/ding) (Flutter + API Node/PostgreSQL).
> Périmètre : tout le dépôt (`lib/`, `api/`, CI, assets, config).
> Date : 9 novembre 2026.
> **Version corrigée : 0.2.0** — l'état de chaque point est récapitulé au §12.

---

## 1. Verdict en une page

Le projet est **bien au-dessus du prototype habituel** :

- la promesse produit est limpide et tient en une phrase ;
- le modèle de confidentialité est pensé **côté serveur** (aucune route ne révèle
  qui a choisi qui, ni les positions) — c'est la bonne architecture, et c'est
  rare à ce stade ;
- le croisement des choix est fait en **une requête SQL** (`checkAlarms`) qui
  gère réciprocité, fraîcheur des positions, distance Haversine et
  anti-harcèlement (1 alarme/heure/paire) d'un coup ;
- le design system est cohérent (une palette, un seul rouge réservé à l'alarme,
  typographie tenue, animations seulement sur l'écran d'alarme) ;
- la CI construit déjà un APK installable.

Les cinq choses qui coûtent le plus cher aujourd'hui :

| # | Problème | Impact |
|---|---|---|
| 1 | **L'app ne sonne pas.** L'écran d'alarme ne fait que vibrer. | Le nom du produit ment ; sans ça, Ding n'est pas une alarme. |
| 2 | **Le bouton « Choisir » est un interrupteur.** Un double appui, ou un réessai après timeout réseau, **annule** le choix. | Bug visible en utilisation réelle ; le pire bug possible dans une app de crush. |
| 3 | **La position n'est envoyée qu'au premier plan**, sans que l'utilisateur le sache ni ne soit alerté si elle est coupée. | La promesse « ça sonne quand vous êtes proches » ne tient pas en pratique. |
| 4 | **Aucune protection hors `/auth`** côté API (pas de limite de débit sur `/location`). | Un seul compte peut marteler la requête SQL la plus coûteuse du système. |
| 5 | **Le dépôt n'a pas de `.gitignore` racine.** | `build/`, `.env`, `*.jks` peuvent être committés un jour par accident. |

Les points 1, 2, 3, 4 et 5 sont **déjà corrigés** dans le patch livré avec cet
audit (voir §2). Le reste est classé par gravité dans les sections suivantes.

---

## 2. Corrections déjà appliquées

> La liste complète et datée des changements de la version 0.2.0 est dans
> [`CHANGELOG.md`](CHANGELOG.md). Le tableau ci-dessous garde les corrections
> issues de la première passe d'audit ; le §12 fait le point sur **tous** les
> points de l'audit.

| Fichier | Problème | Correction |
|---|---|---|
| `.gitignore` *(nouveau)* | Aucun `.gitignore` racine | Fichiers Flutter/Dart/Android/secrets ignorés |
| `lib/data/repository.dart` | `toggleCrush()` inversait l'état à chaque appel | `setCrush(id, active:)` → `POST`/`DELETE` |
| `lib/features/discover/discover_page.dart` | Double appui = choix annulé ; tous les boutons clignotaient pendant le rechargement | État local optimiste, verrou par ligne, retour arrière si échec, spinner, `RefreshIndicator`, `Semantics` |
| `lib/features/profile/profile_page.dart` | Le profil était recopié dans les champs **depuis `build()`** → la saisie en cours était écrasée | Hydratation unique via `ref.listenManual` dans `initState` |
| `lib/features/home/home_shell.dart` | Minuteur actif en arrière-plan ; pas de retour immédiat au premier plan ; aucune alerte si GPS/permission coupés ; plusieurs `/ring` empilables | `WidgetsBindingObserver`, bandeau d'alerte + accès aux réglages, verrou anti-empilement |
| `lib/features/alarm/ring_page.dart` | **L'alarme ne sonnait pas** | Son embarqué `assets/audio/ding.wav` (généré, bouclé) + `audioplayers`, bouton « Couper le son », arrêt garanti dans `dispose()` |
| `lib/data/api_client.dart` | Toutes les erreurs réseau étaient confondues ; timeout de 60 s | `TimeoutException` / `SocketException` distinguées, messages dédiés, message explicite si l'API n'est pas configurée, `dispose()` |
| `lib/core/config.dart` | Adresse d'API par défaut factice → échec silencieux | `Config.isConfigured`, intervalles centralisés |
| `lib/core/providers.dart` | `sessionProvider` en boucle manuelle ; fuite du client HTTP | `yield*`, `ref.onDispose` |
| `api/src/index.js` | Double appui = choix annulé ; pas de limite de débit hors auth ; énumération de comptes par timing ; caractères de contrôle acceptés | Routes idempotentes, `apiLimiter`/`locationLimiter`, `bcrypt.compare` systématique, `clean()` renforcé |
| `api/src/db.js` | Pas d'index sur les colonnes référencées ; positions conservées indéfiniment | Index `crushes(to_user)`, `alarms(user_b)`, `alarms(created_at)` ; purge des positions > 24 h et alarmes > 30 j |
| `.github/workflows/build-apk.yml` | APK publié même sans `API_URL` ; ni analyse ni tests | Job `check` (`flutter analyze`, `flutter test`), échec explicite si `API_URL` manque, vérification des permissions du manifeste |
| `.github/workflows/api.yml` *(nouveau)* | L'API n'était jamais testée | Démarrage réel contre PostgreSQL jetable + parcours critique (inscription → choix réciproques → position → alarme) |
| `test/models_test.dart` *(nouveau)* | Aucun test | Tests de `Profile` et `AlarmItem` (champs null, dates ISO) |
| `analysis_options.yaml` | 1 seule ligne | Lints ciblés, `unawaited_futures` en warning |
| `api/package-lock.json` *(nouveau)* | Builds non reproductibles | Lockfile versionné, `npm ci` en CI |
| `README.md` | Vide | Documentation réelle (démarrage, structure, limites, feuille de route) |

Vérifications faites de mon côté : l'API modifiée démarre, et le parcours
complet (inscription, choix croisés, idempotence, position, alarme, erreurs)
répond correctement **sur une base simulée**. Le SQL n'a pas pu être exécuté
faute de PostgreSQL dans mon environnement : le workflow `api.yml` le fera
tourner pour de vrai dans GitHub Actions.

---

## 3. Bugs restants

### P0 — à corriger avant toute diffusion large

**3.1 `Précision GPS insuffisante pour un rayon de 150 m`** — `home_shell.dart`
La position est demandée en `LocationAccuracy.medium` (~100 m d'erreur sur
Android, parfois plus). Avec un rayon de 150 m, l'erreur de mesure seule peut
faire sonner l'alarme à 300 m ou la taire à 50 m. C'est le cœur du produit.
→ Demander `LocationAccuracy.high` pour l'envoi qui déclenche `checkAlarms`,
ou faire converger le rayon et la précision (ex. 300 m avec `medium`).

**3.2 Une seule alarme affichée si plusieurs arrivent** — `home_shell.dart`
`fresh.first` est présenté, puis `seenAlarmsProvider` marque **tout** comme vu :
les autres alarmes de la même fenêtre de 20 s ne sonneront jamais. Elles
apparaissent dans l'historique, donc ce n'est pas une perte de données, mais
c'est une perte de signal.
→ Soit une file d'attente d'écrans d'alarme, soit une notification par alarme.

**3.3 `AlarmItem.fromMap` casse si un champ requis est null** — `data/models.dart`
`m['alarm_id'] as String` et `DateTime.parse(m['created_at'] as String)`
lèvent une exception sur une réponse inattendue, ce qui met la liste entière en
état d'erreur. Les champs `other_name` sont, eux, déjà tolérants : incohérent.
→ Utiliser des casts nullables + une valeur de repli, ou `tryParse`.

**3.4 `/ring` sans `extra` plante** — `core/router.dart`
`state.extra as AlarmItem` lève une erreur si la route est ouverte sans objet
(lien profond, futur tap sur une notification, restauration d'état).
→ `extra is AlarmItem ? ... : redirect('/home')`.

### P1 — à corriger rapidement

**3.5 `/health` ne vérifie pas la base** — `api/src/index.js`
La route répond `{ok:true}` même si PostgreSQL est injoignable : un moniteur
comme UptimeRobot ne verra rien.
→ `select 1` avant de répondre, et code 503 en cas d'échec.

**3.6 Aucun journal de requêtes** — `api/src/index.js`
En production sur Render, une erreur 500 n'est visible que par le `console.error`
du handler. Impossible de savoir quelle route a échoué.
→ Ajouter un log minimal (méthode, route, statut, durée, `req.uid`), sans jamais
logger le corps des requêtes (mots de passe) ni les positions.

**3.7 `firstLoad` traite aussi les reprises après erreur comme un démarrage**
— `home_shell.dart`. Après une coupure réseau, la première liste revenue ne
fait sonner aucune alarme. Comportement prudent, mais silencieux.

**3.8 Pas de « mot de passe oublié »** — `auth_page.dart`
Aucun flux de réinitialisation : un utilisateur qui oublie son mot de passe est
définitivement bloqué, et son adresse email est déjà prise (409 à l'inscription).
Pour une app de campus qui va vivre, c'est un vrai problème.
→ Route `POST /auth/forgot` + envoi d'un lien (Resend/Brevo en offre gratuite).

**3.9 Aucune vérification d'email** — `api/src/index.js`
Rien n'empêche de s'inscrire avec l'adresse de quelqu'un d'autre. En mode campus
(`ALLOWED_EMAIL_DOMAIN`), ça contourne complètement la restriction.

**3.10 `ALLOWED_EMAIL_DOMAIN` vide par défaut**
Le « mode campus » est désactivé par défaut, alors que c'est la promesse de
départ. Un inconnu peut s'inscrire et parcourir l'annuaire des étudiants.

### P2 — dette assumée

- `home_shell.dart` : `IndexedStack` construit les trois onglets au démarrage →
  l'annuaire (jusqu'à 500 profils) est chargé même si l'utilisateur reste sur
  « Profil ». Chargement paresseux au premier affichage de l'onglet.
- `alarmsProvider` : un `FutureProvider` qui s'auto-invalide toutes les 20 s
  repasse par un état `loading` à chaque cycle. Un `StreamProvider` (ou
  `keepPreviousData`) éviterait les scintillements.
- `core/rings.dart` : `RingSource` et `RingsPainter` ne sont utilisés nulle part
  (seul `PulsePainter` sert). Code mort — à supprimer ou à réutiliser.
- `assets/images/extra_clouds.jpg` et `extra_heart.jpg` (84 Ko) ne sont
  référencés nulle part : poids mort dans l'APK.
- `alarms_page.dart` : `_format` réimplémente le formatage de date à la main ;
  `intl` (ou `MaterialLocalizations`) gérerait la locale et le format 12/24 h.
- `onboarding_page.dart` : `Image.asset` sans `cacheWidth` décode les JPEG à
  pleine résolution en mémoire. Sur un téléphone d'entrée de gamme, ça se sent.
- `Config.alarmRadiusMeters` est dupliqué entre le Dart et l'API. Les deux
  commentaires disent « doit rester identique » : c'est une promesse qu'aucun
  test ne vérifie. Exposer la valeur via `GET /config`.

---

## 4. Sécurité et vie privée

Ce qui est déjà bien : aucun mot de passe stocké en clair, JWT signé, `uuid`
validés par regex, requêtes paramétrées partout (aucune injection SQL possible),
positions jamais renvoyées à un tiers, `trust proxy` correct pour Render.

**4.1 Jeton JWT en clair dans `SharedPreferences`** — `data/api_client.dart`
`SharedPreferences` est un fichier XML lisible sur un appareil rooté, et il
part dans les sauvegardes Android (`allowBackup` par défaut à `true`).
→ `flutter_secure_storage` (Keystore Android) pour le jeton, et
`android:allowBackup="false"` dans le manifeste.

**4.2 Pas de révocation de jeton** — `api/src/index.js`
`expiresIn: '30d'` sans liste de révocation : un jeton volé reste valable un
mois, et « se déconnecter » ne fait que l'oublier côté client.
→ `users.token_version` comparé au `sub` du JWT, incrémenté au logout.

**4.3 Pas de suppression de compte ni d'export** — aucune route
Droit à l'effacement (RGPD) et simple politesse : l'utilisateur ne peut pas
partir. `on delete cascade` est déjà en place, il ne manque que
`DELETE /me` + un bouton (avec confirmation).

**4.4 Pas de blocage ni de signalement**
Le produit repose sur la réciprocité, ce qui limite le harcèlement — mais
l'annuaire expose le prénom, la faculté et la promotion de tous les inscrits,
et l'écran d'alarme dit « *Untel* est tout près ». Sur un petit campus, ça
identifie vite quelqu'un. Au minimum : un moyen de masquer son profil de
l'annuaire (`discoverable boolean`, opt-out).

**4.5 Pas de limite sur la création de comptes** — `authLimiter` limite à 30
requêtes/15 min **par IP**, mais pas par email ni globalement : de derrière un
NAT de campus, un script peut créer des comptes en série. Un simple compteur
par email + un CAPTCHA à l'inscription suffiraient à tarir ça.

**4.6 Timing sur `/auth/login`** — corrigé (§2) : `bcrypt.compare` tourne
désormais même quand l'email est inconnu. Reste un écart de quelques
millisecondes dû au `select` ; négligeable en pratique.

---

## 5. Performance, batterie, données

**5.1 Deux boucles indépendantes qui ne se parlent pas**
`HomeShell` envoie la position toutes les 2 min ; `alarmsProvider` interroge
`/alarms` toutes les 20 s. Pendant que l'app est ouverte, c'est 3 requêtes/min
en continu, sur un forfait data mobile. Piste : faire retourner les nouvelles
alarmes **dans la réponse à `/location`** (économie d'une boucle complète), et
n'interroger `/alarms` que si la position a bougé de plus de X mètres.

**5.2 `google_fonts` télécharge les polices à l'exécution** — `core/theme.dart`
Au premier lancement, `Instrument Sans` et `Bricolage Grotesque` sont récupérées
sur `fonts.gstatic.com`. Sans réseau (ou avec un forfait épuisé), l'app
s'affiche dans la police système, et le soin typographique disparaît ; le texte
peut aussi « sauter » après chargement.
→ Télécharger les deux `.ttf` dans `assets/fonts/` et déclarer `fonts:` dans
`pubspec.yaml`. Bonus : ça supprime une dépendance réseau au démarrage.

**5.3 La requête `checkAlarms` s'exécute à chaque `/location`**
Elle est déjà bien écrite (jointure sur la clé primaire des deux côtés, filtre
`updated_at` avant le calcul de distance) et les index ajoutés aident. Elle
reste O(crushes de l'utilisateur) : sans problème à l'échelle d'un campus,
mais la limite de débit ajoutée (20/min) est la vraie protection.

**5.4 Positions stockées indéfiniment** — corrigé (§2) : purge à 24 h. À noter :
`checkAlarms` ignore déjà tout ce qui a plus de 15 min, donc ces lignes ne
servaient strictement à rien.

---

## 6. Qualité du code et architecture

**6.1 Le point fort : la séparation est déjà bonne.**
`core/` (config, thème, routeur, providers, peintres) / `data/` (client,
modèles, repository) / `features/` (un dossier par écran) est exactement la
structure qu'on veut. Rien à réorganiser.

**6.2 Le point faible : le repository est un passe-plat.**
`Repository` ne fait que renommer les appels du client HTTP. Ce n'est pas un
problème en soi (c'est un bon point d'accroche pour les tests), mais il
n'apporte aujourd'hui aucune logique : pas de cache, pas de retry, pas de
fusion. On peut soit l'assumer, soit y déplacer la logique de domaine (le vrai
endroit pour « une alarme = réciproque + proche »).

**6.3 Aucun test** avant ce patch. Deux familles à couvrir en priorité :
- les **modèles** (fait : `test/models_test.dart`) ;
- la **logique de découverte** (double appui, échec réseau, retour arrière) —
  testable avec `ProviderContainer` + un faux `Repository`, sans réseau.

**6.4 `analysis_options.yaml` était un fichier d'une ligne.** Des lints ciblés
sont maintenant activés ; `flutter analyze` tourne en CI en mode non bloquant
le temps de nettoyer les remarques restantes (celles de §3 P2 notamment), puis
il faudra le rendre bloquant.

**6.5 Messages d'erreur centralisés à moitié.** Certains écrans affichent
`e.message` (bien), d'autres un texte générique (`'Action impossible. Réessaie.'`)
qui perd l'information utile du serveur (« Un compte existe déjà avec cet
email »). Uniformiser sur `ApiException.message` partout.

**6.6 Constantes magiques.** `Config` centralise les intervalles maintenant,
mais `HomeShell` garde `800 ms` de vibration, `20 s` de timeout GPS, et
`theme.dart` fige des tailles en dur. À terme, un `DingDurations` évite les
divergences.

---

## 7. Build, CI et dépôt

**7.1 Le dossier `android/` n'était pas versionné** — c'était le point le plus
fragile du projet. La CI générait `android/` à chaque build puis le patchait au
`s|...|...|` pour ajouter les permissions et le nom : aucun réglage Android ne
pouvait être versionné, et les `sed` cassaient silencieusement au moindre
changement de template Flutter.

→ **Corrigé autrement que prévu** : le projet Gradle reste généré (committer
les ~40 fichiers de plomberie Android apporte peu), mais les **décisions**
Android sont maintenant versionnées dans `tool/android/` (manifeste complet,
politique réseau) et appliquées par `tool/setup_android.sh`, utilisé à la fois
en local et par la CI. Le script vérifie aussi que `minSdk = 23` (requis par
`flutter_secure_storage`) et que les permissions critiques sont présentes.

Versionner `android/` en entier reste possible : il suffit de retirer `android/`
du `.gitignore`.

**7.2 APK signé avec la clé de debug** — le template Flutter met
`signingConfig = signingConfigs.debug` dans le `buildType release`. L'APK est
donc installable, mais signé avec une clé publique de debug : le Play Store le
refusera, et surtout **cette signature ne pourra jamais être changée** pour les
utilisateurs qui l'ont déjà installé. Dès la première diffusion un peu large, il
faut un keystore de release (conservé dans les secrets GitHub, jamais dans le
dépôt) via `android/key.properties`.

**7.3 Nom de paquet `com.ding`** — trop générique : le Play Store exige un
identifiant unique, généralement inversé sur un domaine possédé
(`com.meganae.ding`). Autant le changer maintenant : après publication, il est
immuable.

**7.4 CI : ni analyse ni tests** avant ce patch — corrigé. Note : `flutter
analyze` est en `continue-on-error` ; à passer en bloquant après nettoyage.

**7.5 Pas de `package-lock.json`** côté API — corrigé (builds reproductibles,
`npm ci`).

**7.6 Version `0.1.0+1`** jamais incrémentée : tous les APK publiés portent le
même `versionCode`, donc impossible de savoir lequel est le plus récent, et le
Play Store refusera le deuxième envoi. → Incrémenter le numéro de build à
chaque publication (`flutter build apk --build-number=$GITHUB_RUN_NUMBER`).

---

## 8. Produit et conformité

Ce sont des remarques de fond, pas du code :

1. **La limite « premier plan » doit être dite dans l'app**, pas seulement dans
   le README. L'onboarding dit « Ding utilise ta position quand l'appli est
   ouverte » — c'est honnête, mais un utilisateur ne comprendra pas pourquoi
   l'alarme ne sonne pas quand les deux téléphones sont en poche. C'est la
   limite n°1 du produit, et la corriger (service de premier plan + géofencing)
   est ce qui transforme l'app en vraie alarme.
2. **L'annuaire ouvert est le vrai risque de vie privée.** Le secret porte sur
   les choix, pas sur l'existence des comptes : n'importe quel inscrit voit
   tous les autres. Sur un campus de quelques centaines de personnes, c'est
   sensible. Un opt-out (`discoverable`) est peu de travail pour beaucoup de
   tranquillité.
3. **Pas d'âge minimum, pas de CGU, pas de politique de confidentialité.** Pour
   une app qui collecte la position précise de personnes, c'est le minimum
   attendu (et une exigence des stores).
4. **Le nom « Ding »** est très court, donc difficile à protéger et à trouver
   sur les stores. À vérifier avant de communiquer dessus.

---

## 9. Plan d'action suggéré

**Cette semaine** (le patch fourni couvre l'essentiel) :
1. Fusionner les corrections de §2, lancer `flutter pub get` puis
   `flutter build apk --debug` pour valider (le son et `audioplayers` sont les
   seuls ajouts de dépendance).
2. Tester sur un vrai téléphone : deux comptes, deux appareils, positions
   proches → vérifier que **ça sonne**.
3. Passer `LocationAccuracy.high` (§3.1) et versionner `android/` (§7.1).

**Semaine suivante** :
4. `/health` avec vérification base + journal de requêtes (§3.5, §3.6).
5. Mot de passe oublié + vérification d'email (§3.8, §3.9).
6. `flutter_secure_storage` pour le jeton + `allowBackup=false` (§4.1).
7. `DELETE /me` + suppression de compte dans l'app (§4.3).

**Ensuite, le vrai saut de qualité** :
8. Service de premier plan Android + géofencing, pour que l'alarme sonne même
   app fermée. C'est le chantier qui décide si Ding est une blague de promo ou
   un produit.
9. Notifications push (FCM) plutôt que le polling 20 s : batterie, instantanéité,
   et ça ouvre la porte à un vrai serveur d'envoi.

---

## 10. Détails à la marge

- `auth_page.dart` : le champ mot de passe n'a ni `autofillHints:
  [AutofillHints.password]` ni bascule « afficher » ; les gestionnaires de mots
  de passe ne le remplissent pas correctement.
- `auth_page.dart` : `_signup` démarre à `false`, donc l'écran par défaut est la
  connexion alors que la majorité des visiteurs sont de nouveaux inscrits.
- `onboarding_page.dart` : « Passer » écrit `onboarding_done = true` — un
  utilisateur qui passe ne verra jamais les explications sur la position.
- `router.dart` : pas de `errorBuilder`, donc un chemin inconnu affiche l'écran
  d'erreur rouge de go_router.
- **Contraste de l'écran d'alarme** : `paper` (`#F3F5F9`) sur `signal`
  (`#E5383B`) = **3,88:1**, sous le seuil AA de 4,5:1 pour du texte courant —
  or la phrase « Vous vous êtes choisis. Levez les yeux. » est en 16 px. Le
  titre en 40 px gras passe, lui, le seuil « grand texte » (3:1). Assombrir le
  rouge en `#D32F2F` suffit (4,56:1) et garde exactement le même caractère.
- `theme.dart` : `DingColors.slate` sur `paper` = 5,5:1 (AA confortable) ;
  `ink` sur `paper` = 15,8:1. Le reste de la palette est bon.
- `RingPage` : le bouton « Fermer » est le seul moyen de sortir ; le geste
  « retour » Android fonctionne aussi mais n'est pas indiqué.
- `AlarmItem.otherFaculty` est affiché dans l'historique alors que l'écran
  d'alarme n'affiche que le prénom : incohérence mineure, mais assumée ?

---

## 11. Comment appliquer ce patch

Tout est déjà présent dans le dossier de travail, et un fichier
`ameliorations.patch` (à côté du dépôt, pas dedans) contient l'ensemble des
modifications sous forme de diff applicable.

Vérifié : le patch s'applique sans conflit sur un clone neuf de `main`.

**Option A — récupérer les fichiers directement (le plus simple)**
Copie le dossier `ding/` du workspace par-dessus ton clone, puis :

```bash
cd ding
flutter pub get          # nouvelle dépendance : audioplayers
git add -A
git commit -m "Correctifs d'audit : alarme sonore, choix idempotents, robustesse API et CI"
git push
```

**Option B — appliquer le diff**

```bash
cd ding
git checkout -b ameliorations
git apply --check ../ameliorations.patch   # vérifie avant d'appliquer
git apply ../ameliorations.patch
flutter pub get
git add -A && git commit -m "Correctifs d'audit"
```

**Après application, à vérifier en premier :**

1. `flutter pub get` puis `flutter analyze` (les seuls risques de compilation
   concernent la nouvelle dépendance `audioplayers` et le son embarqué).
2. `flutter run` sur un téléphone réel : deux comptes, deux appareils,
   positions proches → l'écran rouge doit **sonner** et vibrer.
3. `flutter test` → les tests des modèles doivent passer.
4. Pousser : la CI lance l'analyse, les tests, l'APK, et le test de l'API
   contre un vrai PostgreSQL.

**À défaire si besoin** — trois changements sont des choix de produit, pas des
correctifs, et se retirent facilement :

- le son de l'alarme (`audioplayers` + `assets/audio/ding.wav`) ;
- les routes `POST`/`DELETE /crushes/:id` (l'ancienne `/toggle` est conservée,
  donc l'app reste compatible avec une API non redéployée) ;
- le job `check` de la CI, qui ajoute ~2 min à chaque push.


---

## 12. Statut après la version 0.2.0

Légende : ✅ fait · 🟡 partiel · ⬜ ouvert (et pourquoi).

### Bugs

| Réf. | Point | Statut |
|---|---|---|
| 3.1 | Précision GPS insuffisante pour 150 m | ✅ `LocationAccuracy.high` + timeout de 25 s |
| 3.2 | Une seule alarme affichée sur plusieurs | ✅ file d'attente, présentées l'une après l'autre |
| 3.3 | `AlarmItem.fromMap` cassait la liste | ✅ `tryFromMap` : les lignes inutilisables sont ignorées |
| 3.4 | `/ring` sans `extra` plantait | ✅ redirection vers `/home` + page d'erreur du routeur |
| 3.5 | `/health` ne vérifiait pas la base | ✅ `select 1`, réponse 503 en cas de panne |
| 3.6 | Aucun journal de requêtes | ✅ méthode, route, statut, durée (`req.uid` tronqué, jamais le corps) |
| 3.7 | Reprise après erreur traitée comme un démarrage | ✅ `_firstSyncDone` + alarmes vues persistées |
| 3.8 | Pas de mot de passe oublié | ✅ code à 6 chiffres par email + écran dédié |
| 3.9 | Aucune vérification d'email | ⬜ nécessite le même socle email que 3.8 : faisable en ~2 h maintenant que `mailer.js` existe |
| 3.10 | `ALLOWED_EMAIL_DOMAIN` vide par défaut | ⬜ **choix produit** : l'activer bloque tous les inscrits hors domaine. À décider à la rentrée, pas techniquement |

### Sécurité et vie privée

| Réf. | Point | Statut |
|---|---|---|
| 4.1 | Jeton en clair dans `SharedPreferences` | ✅ `flutter_secure_storage` + `allowBackup=false` + migration des sessions existantes |
| 4.2 | Pas de révocation de jeton | ⬜ coût : une requête SQL par appel. À faire si un jeton fuit un jour |
| 4.3 | Pas de suppression de compte | ✅ `DELETE /me` protégé par mot de passe, cascade complète |
| 4.4 | Pas de blocage ni de signalement | 🟡 **visibilité** faite (on peut disparaître de l'annuaire) ; le blocage d'un profil reste ouvert |
| 4.5 | Création de comptes en série | 🟡 limite par IP + verrouillage par compte ; un CAPTCHA reste à ajouter |
| 4.6 | Timing sur `/auth/login` | ✅ |

### Performance et qualité

| Réf. | Point | Statut |
|---|---|---|
| 5.1 | Deux boucles qui ne se parlent pas | ⬜ optimisation à faire *avec* le service de premier plan |
| 5.2 | `google_fonts` télécharge les polices | ⬜ il faut télécharger les `.ttf` et déclarer `fonts:` — 20 min, à faire avant une diffusion large |
| 5.3 | `checkAlarms` à chaque position | 🟡 index + limite de débit ; la fusion dans `/location` reste ouverte |
| 5.4 | Positions stockées indéfiniment | ✅ purge à 24 h |
| 6.3 | Aucun test | ✅ modèles, client HTTP, repository |
| 6.5 | Messages d'erreur à moitié génériques | ✅ `ApiException.message` partout |

### Build et CI

| Réf. | Point | Statut |
|---|---|---|
| 7.1 | `android/` non versionné, `sed` fragiles | ✅ `tool/setup_android.sh` + manifeste de référence |
| 7.2 | APK signé avec la clé de debug | ⬜ nécessite un keystore : **à faire avant toute diffusion large** |
| 7.3 | Nom de paquet `com.ding` | ✅ `com.meganae.ding` (immuable après publication) |
| 7.4 | CI sans analyse ni tests | ✅ analyse (non bloquante), tests, parcours API réel |
| 7.5 | Pas de `package-lock.json` | ✅ |
| 7.6 | `versionCode` jamais incrémenté | ✅ `+2` en 0.2.0, numéro de build CI automatique |

### Ce qui reste, par ordre de priorité

1. **Service de premier plan + notification prioritaire** — le seul chantier
   qui change la nature du produit. Guide complet dans
   [`docs/alarme-en-arriere-plan.md`](docs/alarme-en-arriere-plan.md).
2. **Signature de l'APK** (7.2) — avant de partager le lien à plus de trois
   personnes.
3. **Polices embarquées** (5.2) — 20 minutes, gros effet sur la première
   impression dans un contexte de réseau coûteux.
4. **Vérification d'email** (3.9) — le socle est en place.
5. **Blocage / signalement** (4.4) et **CGU + politique de confidentialité**
   (§8) — deviennent obligatoires dès qu'il y a de vrais utilisateurs.
