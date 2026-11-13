import 'package:ding/features/moderation/moderation_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_api.dart';

/// Une personne signalée par deux fois, telle que l'API la renvoie.
const _aliceId = '11111111-1111-1111-1111-111111111111';

Map<String, dynamic> _queue() => {
      'items': [
        {
          'id': _aliceId,
          'first_name': 'Alice',
          'faculty': 'Médecine',
          'banned': false,
          'reports': 2,
          'open_reports': 2,
          'reasons': ['harcelement'],
          'last_reason': 'harcelement',
          'last_details': 'continue après un blocage',
        },
      ],
      'total': 1,
      'open_reports': 2,
    };

void main() {
  FakeApi queueApi() => FakeApi((method, uri) {
        if (method == 'GET' && uri.path == '/admin/reports') return _queue();
        if (method == 'POST' && uri.path.endsWith('/resolve')) {
          return {'ok': true, 'status': 'dismissed', 'resolved': 2};
        }
        return null;
      });

  testWidgets('la file affiche la personne, le nombre de signalements et le motif',
      (tester) async {
    final app = await buildTestApp(api: queueApi());
    await pumpPhone(tester, app.wrap(const ModerationPage()));

    expect(find.text('Signalements'), findsOneWidget);
    expect(find.text('Alice'), findsOneWidget);
    expect(find.text('Médecine'), findsOneWidget);
    expect(find.text('2 signalements · Harcèlement'), findsOneWidget);
    expect(find.textContaining('continue après un blocage'), findsOneWidget);
  });

  testWidgets('classer sans suite envoie l’action et prévient que c’est fait',
      (tester) async {
    final api = queueApi();
    final app = await buildTestApp(api: api);
    await pumpPhone(tester, app.wrap(const ModerationPage()));

    await tester.tap(find.text('Alice'));
    await tester.pumpAndSettle();

    expect(find.text('Suspendre le compte'), findsOneWidget);

    await tester.enterText(
      find.byType(TextField),
      'rien de répréhensible',
    );
    await tester.tap(find.text('Classer sans suite'));
    await tester.pumpAndSettle();

    expect(api.called('POST /admin/reports/$_aliceId/resolve'), isTrue);
    final body = api.body('POST /admin/reports/$_aliceId/resolve');
    expect(body?['action'], 'dismiss');
    expect(body?['note'], 'rien de répréhensible');
    expect(find.text('Signalement classé sans suite.'), findsOneWidget);
  });

  testWidgets('suspendre demande une confirmation avant d’agir',
      (tester) async {
    final api = queueApi();
    final app = await buildTestApp(api: api);
    await pumpPhone(tester, app.wrap(const ModerationPage()));

    await tester.tap(find.text('Alice'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Suspendre le compte'));
    await tester.pumpAndSettle();

    // La boîte de confirmation explique les conséquences ; rien n'est envoyé
    // tant qu'on n'a pas confirmé.
    expect(find.text('Suspendre Alice ?'), findsOneWidget);
    expect(api.called('POST /admin/reports/$_aliceId/resolve'), isFalse);

    await tester.tap(find.widgetWithText(FilledButton, 'Suspendre'));
    await tester.pumpAndSettle();

    final body = api.body('POST /admin/reports/$_aliceId/resolve');
    expect(body?['action'], 'ban');
    expect(find.text('Alice est suspendu.'), findsOneWidget);
  });

  testWidgets('annuler la confirmation ne suspend personne', (tester) async {
    final api = queueApi();
    final app = await buildTestApp(api: api);
    await pumpPhone(tester, app.wrap(const ModerationPage()));

    await tester.tap(find.text('Alice'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Suspendre le compte'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Annuler'));
    await tester.pumpAndSettle();

    expect(api.called('POST /admin/reports/$_aliceId/resolve'), isFalse);
    expect(find.text('Alice'), findsOneWidget, reason: 'la file reste ouverte');
  });

  testWidgets('l’historique montre les comptes suspendus et permet de les réactiver',
      (tester) async {
    final api = FakeApi((method, uri) {
      if (method == 'GET' && uri.path == '/admin/reports') {
        final tous = uri.queryParameters['status'] == 'all';
        return tous
            ? {
                'items': [
                  {
                    'id': _aliceId,
                    'first_name': 'Alice',
                    'banned': true,
                    'reports': 4,
                    'open_reports': 0,
                    'reasons': ['harcelement'],
                  },
                ],
                'total': 1,
                'open_reports': 0,
              }
            : {'items': <dynamic>[], 'total': 0, 'open_reports': 0};
      }
      if (method == 'POST' && uri.path.endsWith('/restore')) {
        return {'ok': true};
      }
      return null;
    });

    final app = await buildTestApp(api: api);
    await pumpPhone(tester, app.wrap(const ModerationPage()));

    expect(find.text('Rien à traiter'), findsOneWidget);

    await tester.tap(find.byTooltip('Voir aussi les comptes suspendus'));
    await tester.pumpAndSettle();

    expect(find.text('Alice'), findsOneWidget);
    expect(find.text('Compte suspendu'), findsOneWidget);

    await tester.tap(find.text('Alice'));
    await tester.pumpAndSettle();
    expect(find.text('Réactiver le compte'), findsOneWidget);
    expect(find.text('Suspendre le compte'), findsNothing);

    await tester.tap(find.text('Réactiver le compte'));
    await tester.pumpAndSettle();

    expect(api.called('POST /admin/users/$_aliceId/restore'), isTrue);
    expect(find.text('Alice peut de nouveau se connecter.'), findsOneWidget);
  });

  testWidgets('une file vide explique à quoi elle sert', (tester) async {
    final app = await buildTestApp(
      api: FakeApi((method, uri) => method == 'GET' && uri.path == '/admin/reports'
          ? {'items': <dynamic>[], 'total': 0, 'open_reports': 0}
          : null),
    );
    await pumpPhone(tester, app.wrap(const ModerationPage()));

    expect(find.text('Rien à traiter'), findsOneWidget);
    expect(find.textContaining('Aucun signalement en attente'), findsOneWidget);
  });
}
