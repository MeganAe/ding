import 'package:ding/features/legal/legal_page.dart';
import 'package:ding/features/legal/legal_texts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_api.dart';

void main() {
  testWidgets('les conditions d’utilisation s’affichent en entier',
      (tester) async {
    final app = await buildTestApp(api: FakeApi((_, __) => null));
    await pumpPhone(tester, app.wrap(const LegalPage(doc: termsDoc)));

    expect(find.text('Conditions d’utilisation'), findsOneWidget);
    expect(find.text('DING · DOCUMENT LÉGAL'), findsOneWidget);
    expect(find.textContaining(legalVersion), findsOneWidget);
    expect(find.text('1. Ce qu’est Ding'), findsOneWidget);

    // Les articles hors écran ne sont construits qu'en défilant : on va
    // jusqu'au dernier pour vérifier qu'il existe bien.
    await tester.scrollUntilVisible(
      find.text('10. Droit applicable'),
      400,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('10. Droit applicable'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('Une question, une contestation ?'),
      400,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.textContaining('Une question, une contestation ?'),
        findsOneWidget);
  });

  testWidgets('la page confidentialité cite les durées de conservation',
      (tester) async {
    final app = await buildTestApp(api: FakeApi((_, __) => null));
    await pumpPhone(tester, app.wrap(const LegalPage(doc: privacyDoc)));

    expect(find.text('Confidentialité'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('4. Combien de temps'),
      400,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.textContaining('24 heures'), findsWidgets);
  });

  test('les deux textes sont versionnés et ont une adresse de contact', () {
    expect(legalVersion, isNotEmpty);
    expect(contactEmail, contains('@'));
    expect(termsDoc.sections.length, greaterThanOrEqualTo(10));
    expect(privacyDoc.sections.length, greaterThanOrEqualTo(8));
  });
}
