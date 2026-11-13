import 'package:ding/features/auth/auth_page.dart';
import 'package:ding/features/legal/legal_page.dart';
import 'package:ding/features/legal/legal_texts.dart';
import 'package:ding/features/moderation/moderation_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_api.dart';

/// Vérifie les nouveaux écrans sur un petit téléphone : un débordement de
/// mise en page ne fait pas échouer un test fonctionnel, mais il casse
/// l'affichage.
Future<void> pumpSmall(WidgetTester tester, Widget app) async {
  tester.view.physicalSize = const Size(360, 740) * 3;
  tester.view.devicePixelRatio = 3;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
  await tester.pumpWidget(app);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('signalements tient sur 360 px', (tester) async {
    final app = await buildTestApp(
      api: FakeApi((method, uri) => method == 'GET'
          ? {
              'items': [
                {
                  'id': '11111111-1111-1111-1111-111111111111',
                  'first_name': 'Barthélemy',
                  'faculty': 'Sciences économiques',
                  'banned': false,
                  'reports': 12,
                  'open_reports': 12,
                  'reasons': ['harcelement', 'faux_profil', 'intimidation'],
                  'last_details':
                      'M’a écrit dix fois en trois jours malgré un blocage, '
                          'avec un ton menaçant.',
                },
              ],
              'total': 1,
              'open_reports': 12,
            }
          : null),
    );
    await pumpSmall(tester, app.wrap(const ModerationPage()));
    expect(find.text('Barthélemy'), findsOneWidget);
  });

  testWidgets('les textes légaux tiennent sur 360 px', (tester) async {
    final app = await buildTestApp(api: FakeApi((_, __) => null));
    await pumpSmall(tester, app.wrap(const LegalPage(doc: privacyDoc)));
    expect(find.text('Confidentialité'), findsOneWidget);
  });

  testWidgets('la connexion tient sur 360 px', (tester) async {
    final app = await buildTestApp(api: FakeApi((_, __) => null));
    await pumpSmall(tester, app.wrap(const AuthPage()));
    expect(find.text('Me connecter'), findsOneWidget);
  });
}
