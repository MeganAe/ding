# Journal des modifications

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
