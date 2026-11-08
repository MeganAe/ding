# Ding

Une alarme qui sonne seulement quand le choix est réciproque et que les deux personnes sont proches.

## 1. Préparer le projet Flutter

Ce dossier contient le code (`lib/`, `pubspec.yaml`, `assets/`, `supabase/`) mais pas les dossiers `android/` et `ios/`. Pour les générer :

```bash
flutter create --org com.ding --project-name ding ding_app
```

Puis copie dans `ding_app/` : `lib/` (remplace l'existant), `pubspec.yaml` (remplace), `assets/`, `supabase/`, `analysis_options.yaml`.
Supprime ensuite `ding_app/test/widget_test.dart` (il référence l'ancien exemple).

```bash
cd ding_app
flutter pub get
```

## 2. Configurer Supabase

1. Crée un projet sur supabase.com.
2. Ouvre SQL Editor, colle tout `supabase/schema.sql`, exécute.
3. Authentication > Providers > Email : pendant les tests, désactive « Confirm email » pour te connecter tout de suite.
4. Project Settings > API : copie l'URL et la clé `anon`.

## 3. Lancer l'app

```bash
flutter run --dart-define=SUPABASE_URL=https://xxxx.supabase.co --dart-define=SUPABASE_ANON_KEY=ta_cle_anon
```

## 4. Permissions

**Android** : dans `android/app/src/main/AndroidManifest.xml`, avant `<application>` :

```xml
<uses-permission android:name="android.permission.INTERNET"/>
<uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION"/>
<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION"/>
```

**iOS** : dans `ios/Runner/Info.plist` :

```xml
<key>NSLocationWhenInUseUsageDescription</key>
<string>Ding utilise ta position pour savoir si un choix réciproque est à proximité.</string>
```

## 5. Tester

- Profil > « Tester l'alarme » affiche l'écran qui sonne, sans rien configurer d'autre.
- Test réel : deux comptes sur deux téléphones, chacun choisit l'autre, les deux restent à moins de 150 m, appli ouverte.

## Mode campus

Dans `lib/core/config.dart`, renseigne `allowedEmailDomain` avec le domaine d'email de l'université. Vide = tout le monde peut s'inscrire.

## Limites de la V1

- La position est envoyée seulement quand l'appli est ouverte (toutes les 2 min). Alarme en arrière-plan : à ajouter ensuite (notifications push FCM + service au premier plan sur Android).
- Les photos de profil et les images d'onboarding sont à ajouter : l'onboarding utilise pour l'instant des ondes dessinées en code. Pour une vraie image, remplace le `CustomPaint` dans `onboarding_page.dart` par `Image.asset('assets/images/onboarding_1.jpg', fit: BoxFit.cover)`.
- Le filtre de domaine d'email est vérifié côté app uniquement. Pour un vrai blocage, ajoute-le aussi dans le trigger `handle_new_user`.
