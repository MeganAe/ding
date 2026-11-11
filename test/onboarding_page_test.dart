import 'package:ding/features/onboarding/onboarding_page.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_api.dart';

void main() {
  Object? aucuneRoute(String method, Uri uri) => null;

  testWidgets('l’onboarding fait défiler ses trois étapes', (tester) async {
    final app = await buildTestApp(api: FakeApi(aucuneRoute));
    await pumpPhone(tester, app.wrap(const OnboardingPage()));

    expect(find.text('Choisis en secret.'), findsOneWidget);

    await tester.tap(find.text('Continuer'));
    await tester.pumpAndSettle();
    expect(find.text('Sans réciprocité, rien ne se passe.'), findsOneWidget);

    await tester.tap(find.text('Continuer'));
    await tester.pumpAndSettle();
    expect(find.text("Quand c'est réciproque et proche, ça sonne."), findsOneWidget);
    // Dernière étape : « Passer » disparaît, le bouton devient « Commencer ».
    expect(find.text('Commencer'), findsOneWidget);
  });

  testWidgets('« Passer » enregistre que l’onboarding est vu', (tester) async {
    final app = await buildTestApp(api: FakeApi(aucuneRoute));
    await pumpPhone(tester, app.wrap(const OnboardingPage()));

    await tester.tap(find.text('Passer'));
    await tester.pumpAndSettle();

    expect(app.prefs.getBool('onboarding_done'), isTrue);
  });
}
