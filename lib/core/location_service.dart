import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

import 'config.dart';
import 'providers.dart';

/// Où en est le suivi de la position.
enum LocationStatus {
  /// Pas encore démarré (première image, ou arrêté).
  idle,

  /// Le GPS du téléphone est coupé.
  off,

  /// La permission a été refusée.
  denied,

  /// On suit, mais l'app doit être visible : le système peut nous arrêter
  /// dès qu'on la met de côté.
  foregroundOnly,

  /// On suit, y compris quand l'app est en arrière-plan (écran éteint,
  /// autre appli au premier plan), grâce au service de premier plan.
  running,
}

/// Faut-il envoyer la position maintenant ?
///
/// Deux raisons d'envoyer : garder le cœur frais (le serveur ignore les
/// positions de plus de 15 minutes, donc sans ça l'alarme ne sonnerait plus
/// si on reste assis quelque part), ou avoir assez bougé pour que ça change
/// quelque chose au croisement.
bool shouldSendPosition({
  required DateTime now,
  required DateTime? lastSentAt,
  required double metersSinceLast,
  required Duration minInterval,
  double minDistanceMeters = 100,
}) {
  if (lastSentAt == null) return true;
  if (now.difference(lastSentAt) >= minInterval) return true;
  return metersSinceLast >= minDistanceMeters;
}

/// Suit la position et l'envoie à l'API.
///
/// Deux sources, volontairement :
///  - un flux de positions (précis, réactif quand on marche) ;
///  - un battement régulier qui renvoie la dernière position connue, pour que
///    le serveur ne considère jamais nos coordonnées comme périmées.
///
/// Le flux tourne dans un service de premier plan Android (notification
/// permanente) : c'est ce qui permet à l'app de continuer à suivre quand elle
/// est mise de côté ou que l'écran est éteint.
class LocationService extends StateNotifier<LocationStatus> {
  LocationService(this._ref) : super(LocationStatus.idle);

  final Ref _ref;

  StreamSubscription<Position>? _stream;
  Timer? _heartbeat;
  Position? _lastPosition;
  Position? _lastSentPosition;
  DateTime? _lastSentAt;
  Duration _interval = Config.locationInterval;

  /// true quand un suivi tourne déjà (start() est idempotent).
  bool get tracking => _stream != null;

  Future<void> start() async {
    if (_stream != null) return;

    if (!await _safe(() => Geolocator.isLocationServiceEnabled(), false)) {
      state = LocationStatus.off;
      return;
    }

    var perm = await _safe(
      () => Geolocator.checkPermission(),
      LocationPermission.denied,
    );
    if (perm == LocationPermission.denied) {
      perm = await _safe(
        () => Geolocator.requestPermission(),
        LocationPermission.denied,
      );
    }
    if (perm == LocationPermission.denied ||
        perm == LocationPermission.deniedForever) {
      state = LocationStatus.denied;
      return;
    }

    // L'intervalle vient du serveur quand il le précise : une valeur changée
    // côté API s'applique sans nouvelle version de l'app.
    final seconds =
        _ref.read(serverConfigProvider).valueOrNull?.locationIntervalSeconds;
    if (seconds != null && seconds > 0) {
      _interval = Duration(seconds: seconds);
    }

    final settings = AndroidSettings(
      // Précision haute : avec `medium` l'erreur de mesure (~100 m) est du même
      // ordre que le rayon de l'alarme (150 m), ce qui fait sonner à tort.
      accuracy: LocationAccuracy.high,
      distanceFilter: 15,
      intervalDuration: const Duration(seconds: 60),
      foregroundNotificationConfig: const ForegroundNotificationConfig(
        notificationTitle: 'Ding veille',
        notificationText:
            'Ta position sert à savoir si quelqu’un t’a choisi tout près. '
            'Elle n’est jamais montrée à personne.',
        notificationChannelName: 'Position',
        setOngoing: true,
        enableWakeLock: true,
      ),
    );

    try {
      _stream = Geolocator.getPositionStream(locationSettings: settings).listen(
        _onPosition,
        // Un incident du GPS (signal perdu, fournisseur qui redémarre) ne doit
        // pas couper le suivi : le battement prendra le relais.
        onError: (_) {},
        cancelOnError: false,
      );
    } catch (_) {
      state = LocationStatus.denied;
      return;
    }

    _heartbeat?.cancel();
    _heartbeat = Timer.periodic(_interval, (_) => _beat());

    state = perm == LocationPermission.always
        ? LocationStatus.running
        : LocationStatus.foregroundOnly;

    // Un premier envoi tout de suite : sinon il faut attendre deux minutes
    // (ou un déplacement) avant que le serveur sache où on est.
    unawaited(_beat());
  }

  /// Relance après un changement de réglage (retour des paramètres système).
  Future<void> restart() async {
    await stop();
    await start();
  }

  Future<void> stop() async {
    await _stream?.cancel();
    _stream = null;
    _heartbeat?.cancel();
    _heartbeat = null;
    if (mounted) state = LocationStatus.idle;
  }

  Future<void> _onPosition(Position p) async {
    _lastPosition = p;
    await _send(p);
  }

  /// Le battement : renvoie la dernière position connue pour garder le cœur
  /// frais côté serveur, même immobile.
  Future<void> _beat() async {
    final p = _lastPosition ??
        await _safe<Position?>(() => Geolocator.getLastKnownPosition(), null);
    if (p != null) await _send(p);
  }

  Future<void> _send(Position p) async {
    final now = DateTime.now();
    final moved = _lastSentPosition == null
        ? double.infinity
        : Geolocator.distanceBetween(
            _lastSentPosition!.latitude,
            _lastSentPosition!.longitude,
            p.latitude,
            p.longitude,
          );

    if (!shouldSendPosition(
      now: now,
      lastSentAt: _lastSentAt,
      metersSinceLast: moved,
      minInterval: _interval,
    )) {
      return;
    }

    try {
      await _ref.read(repositoryProvider).sendLocation(p.latitude, p.longitude);
      _lastSentAt = now;
      _lastSentPosition = p;
      if (mounted && state != LocationStatus.running) {
        // Une position qui part, c'est la preuve que tout fonctionne.
        final perm = await _safe(
          () => Geolocator.checkPermission(),
          LocationPermission.whileInUse,
        );
        if (mounted) {
          state = perm == LocationPermission.always
              ? LocationStatus.running
              : LocationStatus.foregroundOnly;
        }
      }
    } catch (_) {
      // Réseau coupé : le prochain battement réessaiera.
    }
  }

  /// Les appels au plugin peuvent lever (service GPS absent, émulateur…) :
  /// une erreur ici ne doit jamais remonter jusqu'à l'écran.
  Future<T> _safe<T>(Future<T> Function() action, T fallback) async {
    try {
      return await action();
    } catch (_) {
      return fallback;
    }
  }
}

/// Démarré à la première lecture (l'écran d'accueil le surveille).
final locationServiceProvider =
    StateNotifierProvider<LocationService, LocationStatus>((ref) {
  final service = LocationService(ref);
  ref.onDispose(service.stop);
  unawaited(service.start());
  return service;
});
