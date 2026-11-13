import 'package:ding/features/auth/verify_email_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_api.dart';

void main() {
  FakeApi apiAvec({Map<String, dynamic>? me}) => FakeApi((method, uri) {
        if (method == 'GET' && uri.path == '/me') {
          return me ??
              {
                'id': 'u1',
                'first_name': 'Léa',
                'email': 'lea@campus.test',
                'email_verified': false,
              };
        }
        if (method == 'POST' && uri.path == '/auth/verify-email') {
          return {'ok': true};
        }
        if (method == 'POST' && uri.path == '/auth/verify-email/resend') {
          return {'ok': true};
        }
        return null;
      });

  testWidgets('l’écran montre l’adresse et explique la conséquence',
      (tester) async {
    final app = await buildTestApp(api: apiAvec());
    await pumpPhone(tester, app.wrap(const VerifyEmailPage()));

    expect(find.text('Ton adresse email'), findsOneWidget);
    expect(find.textContaining('lea@campus.test'), findsOneWidget);
    expect(find.textContaining('l’alarme ne peut pas sonner'), findsOneWidget);
    expect(find.text('Confirmer'), findsOneWidget);
  });

  testWidgets('un code trop court est refusé sans appel réseau',
      (tester) async {
    final api = apiAvec();
    final app = await buildTestApp(api: api);
    await pumpPhone(tester, app.wrap(const VerifyEmailPage()));

    await tester.enterText(find.byType(TextField), '123');
    await tester.tap(find.text('Confirmer'));
    await tester.pump();

    expect(find.text('Le code fait six chiffres.'), findsOneWidget);
    expect(api.called('POST /auth/verify-email'), isFalse);
  });

  testWidgets('le bon code part à l’API', (tester) async {
    final api = apiAvec();
    final app = await buildTestApp(api: api);
    await pumpPhone(tester, app.wrap(const VerifyEmailPage()));

    await tester.enterText(find.byType(TextField), '482913');
    await tester.tap(find.text('Confirmer'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(api.called('POST /auth/verify-email'), isTrue);
    expect(api.body('POST /auth/verify-email')?['code'], '482913');
  });

  testWidgets('renvoyer un code lance le compte à rebours', (tester) async {
    final api = apiAvec();
    final app = await buildTestApp(api: api);
    await pumpPhone(tester, app.wrap(const VerifyEmailPage()));

    await tester.tap(find.text('Renvoyer un code'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(api.called('POST /auth/verify-email/resend'), isTrue);
    expect(find.textContaining('Nouveau code envoyé'), findsOneWidget);
    expect(find.textContaining('Renvoyer dans'), findsOneWidget);

    // On laisse le minuteur s'éteindre pour ne pas bloquer le test.
    await tester.pump(const Duration(seconds: 61));
  });
}
