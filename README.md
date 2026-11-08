# Ding

Une alarme qui sonne seulement quand le choix est réciproque et que les deux personnes sont proches.

Le dépôt contient deux parties :
- l'app Flutter (`lib/`, `pubspec.yaml`)
- l'API Node.js + PostgreSQL (`api/`, voir `api/README.md`)

## Compiler l'APK avec GitHub Actions

1. Déploie d'abord l'API (voir `api/README.md`) et note son adresse.
2. Dans GitHub : Settings > Secrets and variables > Actions, crée le secret `API_URL` (ex. `https://ding-api.onrender.com`, sans `/` final).
3. Pousse sur `main`, ou lance « Build APK » à la main depuis l'onglet Actions.
4. Télécharge `ding-apk` dans Artifacts : il contient `app-release.apk`.

## En local

```bash
flutter create --org com.ding --project-name ding --platforms=android .
flutter pub get
flutter run --dart-define=API_URL=https://ton-api.onrender.com
```

Ajoute les permissions `INTERNET`, `ACCESS_COARSE_LOCATION` et `ACCESS_FINE_LOCATION` dans `android/app/src/main/AndroidManifest.xml`.

## Mode campus

Côté API : variable `ALLOWED_EMAIL_DOMAIN`. Côté app : `allowedEmailDomain` dans `lib/core/config.dart`.

## Limites de la V1

- La position est envoyée seulement quand l'appli est ouverte (toutes les 2 min), et l'alarme est vérifiée toutes les 8 s. Alarme appli fermée : à ajouter ensuite (notifications push).
- Les photos de profil et les images d'onboarding restent à ajouter.
