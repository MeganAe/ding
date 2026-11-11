import 'package:ding/core/config.dart';
import 'package:ding/core/location_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final maintenant = DateTime(2026, 11, 11, 14, 0);
  const intervalle = Duration(minutes: 2);

  group('shouldSendPosition', () {
    test('envoie toujours la première position', () {
      expect(
        shouldSendPosition(
          now: maintenant,
          lastSentAt: null,
          metersSinceLast: 0,
          minInterval: intervalle,
        ),
        isTrue,
      );
    });

    test('n’envoie pas si rien n’a bougé et que l’intervalle n’est pas passé',
        () {
      expect(
        shouldSendPosition(
          now: maintenant,
          lastSentAt: maintenant.subtract(const Duration(seconds: 30)),
          metersSinceLast: 3,
          minInterval: intervalle,
        ),
        isFalse,
      );
    });

    test('envoie au bout de l’intervalle, même immobile', () {
      // Sans ça, rester assis 20 minutes rendrait la position périmée côté
      // serveur (il ignore tout ce qui date de plus de 15 minutes) et
      // l'alarme ne sonnerait plus.
      expect(
        shouldSendPosition(
          now: maintenant,
          lastSentAt: maintenant.subtract(intervalle),
          metersSinceLast: 0,
          minInterval: intervalle,
        ),
        isTrue,
      );
    });

    test('envoie dès qu’on s’est déplacé de 100 m, sans attendre l’intervalle',
        () {
      expect(
        shouldSendPosition(
          now: maintenant,
          lastSentAt: maintenant.subtract(const Duration(seconds: 20)),
          metersSinceLast: 120,
          minInterval: intervalle,
        ),
        isTrue,
      );
    });

    test('l’intervalle par défaut est celui de la configuration', () {
      expect(Config.locationInterval, const Duration(minutes: 2));
    });
  });
}
