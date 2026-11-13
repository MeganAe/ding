# Journal des modifications

## 0.4.0 — le liseré noir, les polices, et la vérification d'email

Cette version ferme les points restés ouverts du cahier des charges — sauf la
signature de release, volontairement laissée de côté.

### Corrigé : le liseré noir sur Android 8 et 9

Sur un téléphone Android 9, une ligne noire apparaissait sur l'onboarding.
Deux causes, toutes deux traitées :

- **Les barres système gardaient la couleur par défaut du système.** Sur
  Android 8 et 9, cela donne une barre de navigation noire en bas et une barre
  d'état sombre en haut. L'app force maintenant les deux au papier, côté thème
  Android (`tool/android/styles.xml`, pour l'écran de démarrage) et côté Dart
  (`SystemChrome`, dès la première image).
- **Le flou de la photo passait par un filtre d'image GPU.** Sur les appareils
  sans Vulkan — donc Android 8 et 9 — le rendu emprunte le chemin OpenGL ES,
  où ce flou laisse des liserés. La version floue est désormais obtenue en
  décodant l'image à 40 px de large et en la laissant être agrandie : même
  fondu, aucun filtre GPU, même résultat sur tous les téléphones.

### Polices embarquées

`google_fonts` téléchargeait Instrument Sans et Bricolage Grotesque au premier
lancement : l'app s'affichait en police système tant que le réseau n'avait pas
répondu, et restait sans la bonne police hors ligne. Les deux familles sont
maintenant dans `assets/fonts/` (SIL Open Font License, licences incluses) et
la dépendance `google_fonts` a disparu.

### Vérification d'email

- Code à 6 chiffres envoyé à l'inscription, valable 24 h, 5 essais, renvoi une
  fois par minute.
- **Une adresse non vérifiée n'empêche pas d'utiliser l'app** (annuaire, choix
  secrets, profil) mais empêche l'envoi de position : l'alarme ne sonne pas.
  Un compte jetable ne doit pas pouvoir faire sonner un téléphone, sans pour
  autant bloquer quelqu'un dont l'email a atterri dans les indésirables.
- Écran de confirmation, bandeau sur l'accueil, état visible dans le profil.
- Les comptes existants sont marqués vérifiés une seule fois au démarrage :
  déployer cette version ne coupe l'alarme de personne.

### Modération

- **L'équipe est prévenue par email** à chaque nouveau profil signalé (une
  seule fois par personne : resignaler ne noie pas la boîte).
- **Réactivation d'un compte suspendu depuis l'app** : l'écran Signalements
  bascule sur l'historique et propose « Réactiver le compte ».

### Conditions d'utilisation

- **Ré-acceptation** : si la version publiée par l'API (`TERMS_VERSION`) ne
  correspond plus à celle du compte, un dialogue propose de relire puis
  d'accepter. L'app reste utilisable en attendant — on n'enferme personne
  dehors pour un texte.

### Tests

- API : **34** (+6) — position refusée sans vérification, code faux puis code
  épuisé, renvoi limité à une minute, confirmation, réactivation, refus d'un
  compte ordinaire.
- App : **64** (+10) — écran de confirmation (code court, envoi, compte à
  rebours), historique et réactivation côté modération, lecture du profil.

## 0.3.2 — signalements traités, conditions écrites

Deux manques qui empêchaient de mettre l'app entre les mains de quelqu'un :
les signalements ne servaient à rien (aucun moyen de les lire), et il n'y
avait aucun texte à accepter à l'inscription.

### Modération des signalements

- `GET /admin/reports` : une ligne par **personne** signalée, avec le nombre de
  signalements, les motifs et le dernier commentaire. Les plus signalées
  d'abord.
- `POST /admin/reports/:id/resolve` : `dismiss` (classer sans suite) ou `ban`
  (suspendre). Suspendre coupe la connexion, retire le profil de l'annuaire et
  efface la position et les choix de la personne — sans quoi une alarme
  pourrait encore sonner avec un compte qui n'a plus accès à l'app.
- L'identité de la personne qui signale n'est renvoyée par aucune route, pas
  même à l'équipe : dans un campus de quelques centaines de personnes, un
  signalement attribuable ne serait plus fait.
- Les comptes de modération sont désignés par `ADMIN_EMAILS` (variable
  d'environnement), pas par un écran d'administration : impossible de
  s'attribuer le rôle depuis l'app.
- Écran « Signalements » dans le profil des modérateurs : file, motif, note
  interne facultative, confirmation avant suspension. Invisible pour les
  autres comptes, et le serveur revérifie le rôle à chaque appel.

### Conditions d'utilisation et confidentialité

- Deux textes complets, écrits pour être vérifiables : chaque phrase
  correspond à un comportement réel du code (24 h pour la position, 30 jours
  pour les alarmes, ce que voit un modérateur, ce que l'app ne promet pas).
  Fichier : `lib/features/legal/legal_texts.dart`.
- Écrans de lecture accessibles depuis la connexion **et** depuis le profil,
  lisibles sans compte.
- La case « J'accepte les conditions » est obligatoire à l'inscription :
  l'API refuse `POST /auth/signup` sans `accept_terms: true` et enregistre la
  version acceptée (`terms_version`, `terms_accepted_at`).
- `GET /config` publie `terms_version`, pour pouvoir redemander l'acceptation
  quand le texte change.
- L'adresse de contact des textes se règle au build :
  `--dart-define=CONTACT_EMAIL=…`.

### Corrections au passage

- L'écran de connexion respire moins haut (photo à 30 % au lieu de 40 %) pour
  que le bouton « J'ai déjà un compte » reste visible sur un téléphone de
  844 px malgré les liens légaux ajoutés.
- L'API relit le rôle et l'état de suspension du compte à chaque requête
  authentifiée : une suspension prend effet immédiatement, sans attendre
  l'expiration du jeton (30 jours).

### Tests

- API : **28** (+8) — CGU obligatoire, trace de la version, file groupée,
  signalant jamais identifié, classement sans suite, suspension qui coupe
  tout, actions et identifiants invalides.
- App : **51** (+15) — rendu des deux textes et de la file, décision envoyée
  avec sa note, confirmation avant suspension, annulation, refus d'inscription
  sans case cochée, et un test de mise en page sur un écran de 360 px.

## 0.3.1 — l'alarme sonne écran éteint

Jusqu'ici, Ding ne vous localisait que lorsque l'app était ouverte : autant dire
jamais au bon moment. Le suivi vit maintenant dans un service de premier plan
Android.

- **Service de premier plan** (`lib/core/location_service.dart`) : une
  notification permanente « Ding veille », et la position continue d'être
  envoyée quand l'app est en arrière-plan ou l'écran éteint.
- **Deux sources, volontairement** : un flux de positions (précision haute,
  envoi dès 100 m de déplacement) et un battement toutes les 2 minutes qui
  renvoie la dernière position connue. Sans le battement, rester assis une
  demi-heure rendait les coordonnées périmées côté serveur — et le croisement
  ne se faisait plus.
- **L'intervalle vient du serveur** (`GET /config`), plus d'une constante
  recopiée dans l'app.
- **Permission « Toujours »** : un bandeau explique pourquoi elle est
  nécessaire et emmène directement dans les réglages Android. Il est
  escamotable, pour ne pas harceler.
- `ACCESS_BACKGROUND_LOCATION` ajouté au manifeste de référence, avec la
  justification Play Store en commentaire (déclaration « Position en
  arrière-plan » obligatoire).
- 5 tests unitaires sur la règle d'envoi (première position, immobilité,
  intervalle écoulé, déplacement de 100 m) : 36 tests au total.
- `docs/alarme-en-arriere-plan.md` réécrit : ce qui est fait, comment le
  vérifier sur un téléphone, et ce qui reste.

### Ce que ça ne fait pas encore

L'alarme ne sonne pas si l'app est **quittée** (retour arrière, balayage dans
les tâches récentes) : Android détruit alors le service, et le suivi s'arrête.
Il faut pour ça un isolate séparé (`flutter_background_service`) ou des
notifications push FCM — les deux demandent un téléphone et un projet Firebase
pour être vérifiés, donc ils ne sont pas dans cette version.

## 0.3.0 — confiance et contrôle

Cette version ne change pas la promesse de Ding. Elle fait en sorte qu'on
puisse l'utiliser sans se sentir à découvert.

### Blocage et signalement

- **Bloquer quelqu'un** (`POST /blocks/:id`) : la personne disparaît de ton
  annuaire *et du sien*, vos choix mutuels sont effacés, vos alarmes passées
  sont supprimées, et plus aucune alarme ne peut sonner entre vous. La
  vérification est faite côté serveur dans la requête de croisement, pas
  seulement dans l'app.
- **Débloquer** (`DELETE /blocks/:id`), avec la liste des personnes bloquées
  dans l'écran Profil.
- **Signaler** (`POST /reports/:id`) avec un motif (harcèlement, faux profil,
  intimidation, autre). Une seule ligne par paire, mise à jour au lieu d'être
  dupliquée. Aucune décision automatique : le signalement est enregistré pour
  être traité.
- Ces deux gestes sont accessibles depuis l'annuaire, par le menu de chaque
  personne — pas enterrés dans un écran de réglages.

### Annuaire : recherche et pagination côté serveur

- `GET /profiles` accepte `q` (début de prénom, insensible à la casse),
  `limit` (1 à 100) et `offset`, et répond `{items, total, next_offset}`.
  L'ancienne version chargeait 500 profils et filtrait dans le téléphone.
- L'app fait défiler les pages au fur et à mesure et affiche le total
  (« 42 personnes »). La recherche est temporisée à 320 ms.
- L'app accepte encore l'ancienne réponse en tableau : elle peut être publiée
  avant que l'API ne soit déployée.

### Sessions

- Les jetons portent maintenant un identifiant (`jti`) et `POST /auth/logout`
  les révoque côté serveur : un jeton copié ne sert plus à rien après une
  déconnexion. Les jetons émis avant cette version restent valables jusqu'à
  leur expiration, sinon un déploiement déconnecterait tout le monde.
- Purge des jetons révoqués expirés dans la tâche de nettoyage.

### Réglages venus du serveur

- `GET /config` expose le rayon d'alarme et les intervalles. Le rayon n'est
  plus recopié en dur dans l'app : une valeur changée côté serveur s'applique
  sans nouvelle version sur le Play Store.

### Design intérieur

- **Un système de surfaces** : cartes blanches à filet, rayon 18, sans ombre ;
  libellés de section en petites capitales ; pastilles d'initiale colorées
  (`InitialsAvatar`) à la place des avatars vides.
- **Découvrir** : chaque personne est une carte (initiale, prénom, faculté),
  avec un bouton *Choisir* qui devient *Choisi* en fondu et un menu
  d'options. En-tête avec le nombre de personnes, recherche avec bouton
  d'effacement, écran vide qui explique quoi faire.
- **Alarmes** : groupées par jour (« Aujourd'hui », « Hier », « 12 mars »),
  heure et temps relatif (« il y a 4 min »), étiquette *Nouveau*, et un appui
  rouvre l'écran qui sonne.
- **Badge** sur l'onglet Alarmes : le nombre d'alarmes reçues depuis la
  dernière visite, indépendant du fait de les avoir entendues.
- **Profil** : sections (Mon profil, Visibilité, Personnes bloquées, Ta vie
  privée, Le compte) au lieu d'une colonne de champs, avec l'email affiché et
  la liste des blocages.
- **Écran qui sonne** : l'initiale de la personne au centre des ondes, la
  distance, la faculté, un bouton principal et un seul réglage (le son).

### Qualité

- **L'API a maintenant des tests de bout en bout sur une vraie PostgreSQL**
  (`api/test/parcours.test.js`, 20 cas) : comptes, pagination, croisement
  réciproque à 150 m, une alarme par heure, blocage, signalement, révocation.
  Le schéma SQL n'avait jamais été exécuté avant cette version.
- **9 nouveaux tests d'interface** côté Flutter (onboarding, connexion,
  annuaire, alarmes) : 31 tests au total.
- `flutter analyze` est désormais bloquant en CI (il est propre depuis la
  0.2.2), et la CI de l'API exécute la suite `npm test` sur une base jetable.
- Les quotas de l'API sont réglables par l'environnement (`AUTH_RATE_LIMIT`,
  `API_RATE_LIMIT`, `LOCATION_RATE_LIMIT`), ce qui permet aux tests de créer
  des dizaines de comptes sans désactiver la protection.

## 0.2.2 — connexion et inscription dans le langage de l'onboarding

- **Vos photos d'origine sont conservées** : aucune image n'est remplacée ni
  modifiée dans cette version. `onboarding_1.jpg` (600 × 400),
  `onboarding_2.jpg` et `onboarding_3.jpg` (600 × 900), `auth_login.jpg`
  (600 × 900) et `auth_signup.jpg` (600 × 362) sont utilisées telles quelles.
- **Les écrans de connexion et d'inscription reprennent le gabarit de
  l'onboarding** : la photo occupe le haut de l'écran, en pleine largeur, et se
  dissout dans le papier par le même flou progressif. Le fond arrondi de 200 px
  qui enfermait l'image a disparu.
- **Un seul langage pour les deux écrans** : `HeroMedia` (photo + flou fondu +
  voiles) et `PillButton` (pastille d'action secondaire) sont maintenant des
  widgets partagés dans `lib/core/widgets/`. « Passer » sur l'onboarding et
  « Pas encore de compte ? Inscris-toi » sur la connexion sont la même
  pastille ; le bouton principal est le même bouton d'encre, à la même hauteur.
- **La marque s'assoit sur la fin du fondu** : petit logo + « Ding », là où la
  photo est déjà redevenue du papier — la hauteur gagnée va au formulaire.
- **Changement de mode en fondu** : passer de « se connecter » à « s'inscrire »
  fait glisser l'autre photo en fondu enchaîné, sans saut.
- **Le clavier passe devant la photo** : quand un champ prend le focus, la photo
  se replie et le formulaire remonte. L'écran défile (contrairement à
  l'onboarding) : c'est nécessaire, le clavier occupe la moitié de l'écran.
- Pendant l'envoi, le bouton affiche un indicateur circulaire au lieu de son
  libellé ; les messages d'erreur portent une icône et restent lisibles.
- Points d'intérêt (`Alignment`) réglés sur le cadrage réel de chaque photo :
  le couple de `auth_login.jpg` est calé en bas pour tomber juste avant le
  fondu, les deux visages de `auth_signup.jpg` restent nets.
- `flutter analyze` : aucun problème. `flutter test` : 15 tests au vert.
- `pubspec.lock` est maintenant versionné : c'est une application, les builds
  doivent être reproductibles.

## 0.2.1 — onboarding en pleine largeur

- **Les images d'onboarding remplissent maintenant l'écran** : plus de cadre
  arrondi avec des marges, elles prennent toute la largeur et ~65 % de la
  hauteur (`BoxFit.cover`), avec un point d'intérêt réglable par étape.
- **Flou progressif** entre l'image et le texte, puis fondu au papier : la
  séparation se fait sans bord visible. Technique utilisée : une copie de la
  même image, floutée (`ImageFiltered`) et révélée par un dégradé
  (`ShaderMask`) — plus léger et plus progressif qu'un `BackdropFilter`, dont
  la bande aurait un bord net.
- **La page ne défile plus** (elle ne défilait pas avant, mais rien ne
  l'empêchait de déborder) : l'agrandissement du texte système est plafonné à
  125 %, la mise en page se comprime au lieu de déborder.
- **« Passer », la progression et le bouton sont fixes** : seuls l'image et le
  texte défilent horizontalement, ce qui donne un glissement plus calme.
- Léger voile en haut pour garder le bouton « Passer » et les icônes de la
  barre d'état lisibles sur une photo claire.

## 0.2.0 — audit et consolidation

### Corrigé

- **L'alarme sonne.** L'écran rouge ne faisait que vibrer : il joue maintenant
  `assets/audio/ding.wav` en boucle, avec un bouton « Couper le son » et un
  arrêt garanti à la fermeture.
- **« Choisir » n'annule plus un choix.** La route `/crushes/:id/toggle`
  inversait l'état à chaque appel : un double appui (ou un réessai après un
  timeout réseau) retirait le crush. Remplacée par `POST` / `DELETE
  /crushes/:id`, idempotents. L'ancienne route reste disponible pour les
  versions déjà installées.
- **Saisie du profil plus écrasée.** `ProfilePage` recopiait le profil dans les
  champs depuis `build()`, à chaque rechargement du provider.
- **Plusieurs alarmes ne sont plus perdues.** Elles sont mises en file et
  présentées l'une après l'autre.
- **Alarmes vues persistées.** Un redémarrage ne rejoue plus une alarme déjà
  vue, et une reprise après coupure réseau ne « mange » plus une vraie
  nouvelle alarme.
- **Mot de passe oublié.** Il n'existait aucun moyen de récupérer un compte :
  code à 6 chiffres par email + écran dédié, connexion automatique ensuite.
- **Suppression de compte.** `DELETE /me` (mot de passe redemandé), avec
  suppression en cascade des choix, positions et alarmes.
- **Nombreux / 404 au démarrage.** `GET /health` vérifie désormais la base et
  répond 503 en cas de panne.
- **Annonce d'erreur réseau** : timeout, serveur injoignable et API non
  configurée donnent trois messages distincts au lieu d'un « connexion
  impossible » générique.

### Sécurité

- Jeton de session déplacé de `SharedPreferences` vers le Keystore Android
  (`flutter_secure_storage`), avec migration transparente des sessions
  existantes et `allowBackup="false"`.
- Verrouillage temporaire d'un compte après 10 échecs de connexion.
- Réponses identiques sur `/auth/forgot` que l'email existe ou non.
- `bcrypt.compare` exécuté même quand l'email est inconnu (fuite de timing).
- Limites de débit sur toutes les routes authentifiées ; quota spécifique sur
  `/location`, qui déclenche la requête SQL la plus coûteuse.
- Les caractères de contrôle sont retirés des champs texte.
- Les positions de plus de 24 h et les codes de réinitialisation expirés sont
  purgés automatiquement.

### Ajouté

- **Visibilité** : un interrupteur « Apparaître dans l'annuaire » permet de
  disparaître de l'annuaire sans supprimer son compte.
- **Précision GPS haute** pour l'envoi qui déclenche les alarmes (`medium`
  donnait ~100 m d'erreur pour un rayon de 150 m).
- **Bandeau d'alerte** quand le GPS ou la permission de localisation manque,
  avec accès direct aux réglages.
- **Suivi au premier plan maîtrisé** : minuteur coupé en arrière-plan, envoi
  immédiat et rafraîchissement des alarmes au retour.
- **`tool/setup_android.sh`** : le manifeste Android (permissions,
  `allowBackup`, politique réseau, `minSdk 23`) est enfin versionné et
  appliqué par script, au lieu de trois `sed` fragiles dans la CI.
- **CI** : `flutter analyze`, `flutter test`, tests de l'API contre un
  PostgreSQL jetable avec parcours critique complet, échec explicite si le
  secret `API_URL` manque.
- **Tests unitaires** des modèles et du client HTTP (`http/testing.dart`).
- `package-lock.json` versionné (builds API reproductibles).
- `.gitignore` racine : `build/`, `.env`, `*.jks`, `android/` généré.
- Documentation : `README.md` complet, `AUDIT.md` (revue technique),
  `docs/alarme-en-arriere-plan.md` (chantier du service de premier plan).

### Modifié

- Rouge d'alarme assombri (`#E5383B` → `#D32F2F`) : le texte clair dessus
  atteignait 3,88:1, sous le seuil d'accessibilité AA (4,56:1 maintenant).
- Onglets chargés à la demande : l'annuaire n'est plus chargé au démarrage si
  l'utilisateur reste sur un autre onglet.
- Dates d'alarme plus lisibles (« Aujourd'hui à 14:32 »).
- Code mort supprimé (`RingsPainter`, `RingSource`), images décodées à la
  taille d'affichage, routeur avec page d'erreur et garde sur `/ring`.
- Numéro de version incrémenté à chaque build de CI.
