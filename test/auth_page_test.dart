import 'package:ding/features/auth/auth_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_api.dart';

void main() {
  Object? aucuneRoute(String method, Uri uri) => null;

  testWidgets('la connexion bascule vers l’inscription', (tester) async {
    final app = await buildTestApp(api: FakeApi(aucuneRoute));
    await pumpPhone(tester, app.wrap(const AuthPage()));

    expect(find.text('Connecte-toi.'), findsOneWidget);
    expect(find.text('Prénom'), findsNothing);

    await tester.tap(find.text('Pas encore de compte ? Inscris-toi'));
    await tester.pumpAndSettle();

    expect(find.text('Crée ton compte.'), findsOneWidget);
    expect(find.text('Prénom'), findsOneWidget);
    expect(find.text('Créer mon compte'), findsOneWidget);
  });

  testWidgets('un envoi incomplet affiche un message, sans appel réseau',
      (tester) async {
    final api = FakeApi(aucuneRoute);
    final app = await buildTestApp(api: api);
    await pumpPhone(tester, app.wrap(const AuthPage()));

    await tester.tap(find.text('Me connecter'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Renseigne ton email'), findsOneWidget);
    expect(api.calls, isEmpty);
  });

  testWidgets('refuse de créer un compte sans accepter les conditions',
      (tester) async {
    final api = FakeApi(aucuneRoute);
    final app = await buildTestApp(api: api);
    await pumpPhone(tester, app.wrap(const AuthPage()));

    await tester.tap(find.text('Pas encore de compte ? Inscris-toi'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).at(0), 'Léa');
    await tester.enterText(find.byType(TextField).at(1), 'lea@campus.test');
    await tester.enterText(find.byType(TextField).at(2), 'motdepasse');
    await tester.tap(find.text('Créer mon compte'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Coche la case'), findsOneWidget);
    expect(api.calls, isEmpty, reason: 'rien ne part sans acceptation');
  });

  testWidgets('transmet l’acceptation des conditions à l’API',
      (tester) async {
    final api = FakeApi((method, uri) =>
        method == 'POST' && uri.path == '/auth/signup'
            ? {'token': 'jeton-neuf'}
            : null);
    final app = await buildTestApp(api: api);
    await pumpPhone(tester, app.wrap(const AuthPage()));

    await tester.tap(find.text('Pas encore de compte ? Inscris-toi'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).at(0), 'Léa');
    await tester.enterText(find.byType(TextField).at(1), 'lea@campus.test');
    await tester.enterText(find.byType(TextField).at(2), 'motdepasse');
    await tester.tap(find.byType(Checkbox));
    // Pas de `pumpAndSettle` ici : le curseur du champ de saisie clignote tant
    // qu'il garde le focus, et les images ne s'arrêtent donc jamais.
    await tester.pump();

    await tester.tap(find.text('Créer mon compte'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    final body = api.body('POST /auth/signup');
    expect(body?['accept_terms'], isTrue);
    expect(body?['first_name'], 'Léa');
  });

  testWidgets('les deux textes légaux sont accessibles depuis la connexion',
      (tester) async {
    final app = await buildTestApp(api: FakeApi(aucuneRoute));
    await pumpPhone(tester, app.wrap(const AuthPage()));

    expect(find.text('Conditions'), findsOneWidget);
    expect(find.text('Confidentialité'), findsOneWidget);
  });
}
