# Faire sonner l'alarme quand l'app est fermée

> **État actuel (0.3.1)** : l'app suit la position dans un **service de
> premier plan** Android (notification permanente, `GeolocatorLocationService`).
> Résultat : l'alarme peut sonner **écran éteint et app en arrière-plan**.
> Elle ne sonne toujours pas si l'utilisateur **quitte** l'app (bouton retour,
> balayage dans les tâches récentes) : Android détruit alors le service.
> La suite est décrite en §1 bis et §7.

## 1 bis. Ce qui est fait, et comment le vérifier sur un téléphone

Le suivi vit dans `lib/core/location_service.dart` :

- un flux de positions (précision haute, `distanceFilter` 15 m) qui envoie dès
  qu'on s'est déplacé de 100 m ;
- un **battement** toutes les 2 minutes (valeur venue de `GET /config`) qui
  renvoie la dernière position connue. Sans lui, rester assis une demi-heure
  rendrait les coordonnées périmées et le croisement ne se ferait plus ;
- une notification permanente « Ding veille » : sans elle, Android arrête
  l'app au bout de quelques minutes.

Protocole, sur un vrai téléphone (l'émulateur ne rejoue pas correctement la
mise en veille) :

1. Installe l'APK, connecte-toi, autorise la position.
2. Dans les réglages Android de Ding → Autorisations → Position, choisis
   **Toujours autoriser**. Sans ça, l'app affiche un bandeau et le suivi
   s'arrête dès que l'app passe en arrière-plan.
3. Verrouille l'écran, laisse le téléphone tranquille 5 minutes.
4. Côté serveur, vérifie que la position est fraîche :
   `select user_id, updated_at from locations;` — `updated_at` doit bouger
   toutes les 2 minutes.
5. Passe l'app en arrière-plan (bouton accueil), répète l'étape 4.
6. Tue l'app (balayage dans les tâches récentes) : la mise à jour s'arrête.
   C'est la limite assumée de cette version.

---

## 1. Pourquoi ça ne marche pas aujourd'hui

Android gèle les minuteurs (`Timer.periodic`) d'une application dès qu'elle
passe en arrière-plan : le cycle d'envoi de position toutes les 2 minutes
s'arrête, l'interrogation de `/alarms` aussi. Il n'y a pas de solution côté
Dart pur : il faut un composant Android qui vit hors de l'activité.

Deux mécanismes, complémentaires :

| Mécanisme | Ce qu'il apporte | Coût |
|---|---|---|
| **Service de premier plan** (`foreground service`) | L'isolate Dart continue de tourner, notification permanente visible | Batterie, données, politique Play Store |
| **Notification prioritaire** (`fullScreenIntent`) | Réveille l'écran avec l'écran d'alarme, comme un appel | Aucun si une notification est déjà permise |

Et une troisième voie, à considérer sérieusement :

| Mécanisme | Ce qu'il apporte | Coût |
|---|---|---|
| **Push FCM** | Le serveur réveille le téléphone au moment de l'alarme, l'app n'a plus besoin de tourner | Compte Firebase, un peu de serveur |

**Recommandation** : pousser la position via service de premier plan (c'est ce
qui alimente le croisement), et déclencher l'alarme par notification
prioritaire. FCM peut venir après, pour remplacer le polling.

---

## 2. Dépendances à ajouter

```yaml
# pubspec.yaml
dependencies:
  flutter_foreground_task: ^8.17.0
  flutter_local_notifications: ^18.0.1
```

Puis `flutter pub get`. **Vérifie les versions** sur pub.dev : ce sont les deux
seuls points de ce dépôt que je n'ai pas pu compiler.

---

## 3. Manifeste

`tool/android/AndroidManifest.xml` contient déjà les permissions ; il reste à
déclarer le service et les récepteurs :

```xml
<application ...>
    <!-- Service de suivi de position -->
    <service
        android:name="com.pravera.flutter_foreground_task.service.ForegroundService"
        android:foregroundServiceType="location"
        android:exported="false" />

    <!-- Notifications : réveil de l'écran lors d'une alarme -->
    <receiver
        android:name="com.dexterous.flutterlocalnotifications.ScheduledNotificationReceiver"
        android:exported="false" />
    <receiver
        android:name="com.dexterous.flutterlocalnotifications.ScheduledNotificationBootReceiver"
        android:exported="false">
        <intent-filter>
            <action android:name="android.intent.action.BOOT_COMPLETED" />
            <action android:name="android.intent.action.MY_PACKAGE_REPLACED" />
            <action android:name="android.intent.action.QUICKBOOT_POWERON" />
        </intent-filter>
    </receiver>
</application>
```

Ces deux blocs sont fournis par la documentation des plugins : recopie-les
depuis leur README au moment de l'intégration, ils changent selon la version.

---

## 4. Le code, dans les grandes lignes

### a) Lancer le service au démarrage de l'app

```dart
// lib/core/background/tracking.dart
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

Future<void> startTracking() async {
  FlutterForegroundTask.init(
    androidNotificationOptions: AndroidNotificationOptions(
      channelId: 'ding_tracking',
      channelName: 'Suivi de proximité',
      channelDescription:
          'Permet à Ding de savoir quand un choix réciproque est à proximité.',
      channelImportance: NotificationChannelImportance.LOW,
      priority: NotificationPriority.LOW,
    ),
    foregroundTaskOptions: ForegroundTaskOptions(
      eventAction: ForegroundTaskEventAction.repeat(120000), // 2 minutes
      autoRunOnBoot: true,
      allowWakeLock: true,
    ),
  );

  await FlutterForegroundTask.startService(
    notificationTitle: 'Ding est actif',
    notificationText: 'Tu seras prévenu si un choix réciproque est tout près.',
    callback: trackingCallback,
  );
}

@pragma('vm:entry-point')
void trackingCallback() {
  FlutterForegroundTask.setTaskHandler(TrackingHandler());
}
```

### b) Le handler : envoi de position + interrogation des alarmes

⚠️ Il tourne dans **un isolate séparé** : pas de `ProviderScope`, pas de
`BuildContext`, pas d'accès aux providers Riverpod. Il faut reconstruire un
`SharedPreferences`, un `TokenStore` et un `ApiClient` à la main, puis garder
le même contrat HTTP que le reste de l'app (`Repository`).

```dart
class TrackingHandler extends TaskHandler {
  late final Repository _repo;

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    final prefs = await SharedPreferences.getInstance();
    final tokens = TokenStore(prefs);
    await tokens.load();
    _repo = Repository(ApiClient(tokens));
  }

  @override
  void onRepeatEvent(DateTime timestamp) async {
    // 1. envoyer la position (LocationAccuracy.high)
    // 2. GET /alarms
    // 3. si une alarme inconnue (voir SeenAlarms) -> notification prioritaire
  }

  @override
  Future<void> onDestroy(DateTime timestamp) async {}
}
```

La logique de « quelle alarme est nouvelle » existe déjà dans
`SeenAlarms` (`lib/core/providers.dart`) et se réutilise telle quelle : elle ne
dépend que de `SharedPreferences`.

### c) La notification qui réveille l'écran

```dart
final plugin = FlutterLocalNotificationsPlugin();
await plugin.initialize(const InitializationSettings(
  android: AndroidInitializationSettings('@mipmap/ic_launcher'),
));

await plugin.show(
  alarm.id.hashCode,
  '${alarm.otherName} est tout près.',
  'Vous vous êtes choisis. Levez les yeux.',
  const NotificationDetails(
    android: AndroidNotificationDetails(
      'ding_alarms',
      'Alarmes',
      channelDescription: 'Un choix réciproque est à proximité.',
      importance: Importance.max,
      priority: Priority.high,
      fullScreenIntent: true,
      category: AndroidNotificationCategory.alarm,
      playSound: true,
      enableVibration: true,
    ),
  ),
);
```

`fullScreenIntent: true` ouvre l'activité par-dessus l'écran verrouillé : c'est
ce qui donne l'effet « ça sonne ». À combiner avec un `payload` pour naviguer
vers `/ring` via `onDidReceiveNotificationResponse`.

### d) Permissions à l'exécution

| Permission | Quand | API Android |
|---|---|---|
| `ACCESS_FINE_LOCATION` | déjà demandée au premier lancement | 23+ |
| `POST_NOTIFICATIONS` | avant `startService()` | 33+ |
| Service en arrière-plan | jamais si le service reste de type `location` | 34+ |

`FOREGROUND_SERVICE_LOCATION` est déjà dans le manifeste. Sur Android 14, un
service de type `location` démarré **depuis l'arrière-plan** est refusé : il
faut le démarrer depuis l'app visible (ce que fait `startTracking()` au
démarrage), ou passer par l'API `ACCESS_BACKGROUND_LOCATION` — que Google Play
soumet à examen et qui exigerait une justification écrite.

---

## 5. Les pièges qui font échouer ce genre de chantier

1. **Optimisation de la batterie.** Sur Xiaomi, Huawei, Oppo, Samsung, le
   système tue les services de premier plan. Il faut demander explicitement
   `REQUEST_IGNORE_BATTERY_OPTIMIZATIONS` et expliquer à l'utilisateur
   (`FlutterForegroundTask.requestIgnoreBatteryOptimization()`), sinon
   l'alarme ne sonnera tout simplement jamais sur ces téléphones — c'est-à-dire
   sur une grande partie du parc visé.
2. **Le cold start de Render.** Le service interroge `/alarms` toutes les
   20 s ; si l'API gratuite est en veille, la première requête peut prendre une
   minute. Un ping `/health` toutes les 5 minutes (UptimeRobot) règle ça.
3. **Batterie et données.** Une position toutes les 2 minutes en précision
   haute, c'est ~5 à 10 % de batterie par heure. À mesurer avant de diffuser.
4. **Politique Play Store.** Le suivi de position en arrière-plan est un
   « sensitive permission » : formulaire de justification, vidéo de
   démonstration, et possibilité de refus. Prévoir du temps.
5. **Doublons d'alarme.** Le polling de l'isolate et celui de l'UI peuvent
   détecter la même alarme. `SeenAlarms` étant persisté, ils partagent
   l'information : garde impérativement ce point unique.

---

## 6. Protocole de test

1. Deux téléphones, deux comptes, choix réciproques.
2. Sur A : app en arrière-plan, écran éteint.
3. Sur B : se déplacer à moins de 150 m, app ouverte, attendre 2 minutes.
4. Attendu : le téléphone A sonne (écran qui s'allume), avec le son de
   `assets/audio/ding.wav`.
5. Refaire le test après 30 minutes d'écran éteint (c'est là que les
   optimisations constructeur frappent).
6. Refaire sur un Xiaomi ou un Samsung si possible.

---

## 7. Estimation

| Étape | Effort |
|---|---|
| Intégration des deux plugins + manifeste | 2 h |
| Handler de suivi (position + alarmes) | 2 h |
| Notification prioritaire + navigation vers `/ring` | 2 h |
| Demande de désactivation de l'optimisation batterie | 1 h |
| Tests sur appareils réels | 1 journée |

C'est un chantier d'une journée à deux, avec un téléphone Android physique sous
la main. Sans appareil réel, il ne faut pas le commencer.
