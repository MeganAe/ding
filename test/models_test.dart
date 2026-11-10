import 'package:ding/data/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Profile', () {
    test('lit les champs renvoyés par l’API', () {
      final p = Profile.fromMap(const {
        'id': 'a1',
        'first_name': 'Amina',
        'faculty': 'Médecine',
        'promotion': 'L3',
        'discoverable': true,
      });

      expect(p.id, 'a1');
      expect(p.firstName, 'Amina');
      expect(p.initial, 'A');
      expect(p.detail, 'Médecine, L3');
      expect(p.discoverable, isTrue);
    });

    test('tolère un prénom vide et des champs optionnels absents', () {
      final p = Profile.fromMap(const {'id': 'a2', 'first_name': null});

      expect(p.firstName, '');
      expect(p.initial, '?');
      expect(p.detail, '');
      // Absent de la réponse : on considère le profil visible.
      expect(p.discoverable, isTrue);
    });

    test('lit discoverable=false (profil masqué de l’annuaire)', () {
      final p = Profile.fromMap(const {
        'id': 'a3',
        'first_name': 'Bo',
        'discoverable': false,
      });

      expect(p.discoverable, isFalse);
      expect(p.copyWith(discoverable: true).discoverable, isTrue);
    });

    test('ignore les champs optionnels vides dans le détail', () {
      final p = Profile.fromMap(const {
        'id': 'a4',
        'first_name': 'Bo',
        'faculty': '',
        'promotion': 'M1',
      });

      expect(p.detail, 'M1');
    });
  });

  group('AlarmItem', () {
    test('convertit la date ISO du serveur', () {
      final a = AlarmItem.tryFromMap(const {
        'alarm_id': 'x1',
        'created_at': '2026-11-09T10:15:00.000Z',
        'other_id': 'u2',
        'other_name': 'Bo',
        'other_faculty': 'Droit',
      })!;

      expect(a.id, 'x1');
      expect(a.createdAt.isUtc, isTrue);
      expect(a.createdAt, DateTime.utc(2026, 11, 9, 10, 15));
      expect(a.otherName, 'Bo');
      expect(a.otherFaculty, 'Droit');
    });

    test('accepte une alarme sans faculté ni prénom', () {
      final a = AlarmItem.tryFromMap(const {
        'alarm_id': 'x2',
        'created_at': '2026-11-09T10:15:00Z',
        'other_id': 'u3',
        'other_name': null,
      })!;

      expect(a.otherName, '');
      expect(a.otherFaculty, isNull);
    });

    test('rejette une alarme inutilisable sans faire échouer la liste', () {
      expect(AlarmItem.tryFromMap(const {'other_id': 'u4'}), isNull);
      expect(
        AlarmItem.tryFromMap(const {
          'alarm_id': 'x3',
          'created_at': 'pas une date',
          'other_id': 'u5',
        }),
        isNull,
      );
    });
  });
}
