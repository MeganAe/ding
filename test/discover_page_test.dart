import 'package:ding/features/discover/discover_page.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_api.dart';

Object? _campus(String method, Uri uri) {
  if (uri.path == '/crushes') return <String>[];
  // Choisir / retirer quelqu'un.
  if (uri.path.startsWith('/crushes/')) return {'active': method == 'POST'};
  if (uri.path == '/profiles') {
    return {
      'items': [
        {'id': 'u1', 'first_name': 'Alice', 'faculty': 'Médecine'},
        {'id': 'u2', 'first_name': 'Bob'},
      ],
      'total': 2,
      'next_offset': null,
    };
  }
  return null;
}

void main() {
  testWidgets('l’annuaire affiche les profils et le total', (tester) async {
    final app = await buildTestApp(api: FakeApi(_campus));
    await pumpPhone(tester, app.page(const DiscoverPage()));

    expect(find.text('Alice'), findsOneWidget);
    expect(find.text('Bob'), findsOneWidget);
    expect(find.text('2 personnes'), findsOneWidget);
    expect(find.text('Médecine'), findsOneWidget);
  });

  testWidgets('choisir quelqu’un envoie un POST et passe en « Choisi »',
      (tester) async {
    final api = FakeApi(_campus);
    final app = await buildTestApp(api: api);
    await pumpPhone(tester, app.page(const DiscoverPage()));

    await tester.tap(find.text('Choisir').first);
    await tester.pumpAndSettle();

    expect(api.called('POST /crushes/u1'), isTrue);
    expect(find.text('Choisi'), findsOneWidget);
    expect(find.text("Enregistré. Personne n'est prévenu."), findsOneWidget);
  });

  testWidgets('un annuaire vide explique quoi faire', (tester) async {
    final app = await buildTestApp(
      api: FakeApi((m, uri) {
        if (uri.path == '/crushes') return <String>[];
        if (uri.path == '/profiles') {
          return {'items': <Object>[], 'total': 0, 'next_offset': null};
        }
        return null;
      }),
    );
    await pumpPhone(tester, app.page(const DiscoverPage()));

    expect(find.text('Le campus est vide'), findsOneWidget);
  });
}
