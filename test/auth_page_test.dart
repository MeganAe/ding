import 'package:ding/features/auth/auth_page.dart';
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
}
