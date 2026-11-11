# Journal des modifications

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
