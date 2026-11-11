import 'package:ding/features/alarm/alarms_page.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_api.dart';

Object? _routes(String method, Uri uri) {
  if (uri.path == '/config') {
    return {
      'alarm_radius_meters': 150,
      'alarm_poll_seconds': 600,
      'location_interval_seconds': 120,
    };
  }
  if (uri.path == '/alarms') {
    final now = DateTime.now();
    return [
      {
        'alarm_id': 'a1',
        'created_at': now.toUtc().toIso8601String(),
        'other_id': 'u1',
        'other_name': 'Alice',
        'other_faculty': 'Médecine',
      },
      {
        'alarm_id': 'a2',
        'created_at': now.subtract(const Duration(days: 3)).toUtc().toIso8601String(),
        'other_id': 'u2',
        'other_name': 'Bob',
      },
    ];
  }
  return null;
}

void main() {
  testWidgets('les alarmes sont groupées par jour', (tester) async {
    final app = await buildTestApp(api: FakeApi(_routes));
    await pumpPhone(tester, app.page(const AlarmsPage()));

    expect(find.text('Alice'), findsOneWidget);
    expect(find.text('Bob'), findsOneWidget);
    expect(find.text("Aujourd'hui"), findsOneWidget);
    // Les deux alarmes sont postérieures à la dernière visite (aucune).
    expect(find.text('Nouveau'), findsNWidgets(2));
  });

  testWidgets('sans alarme, l’écran explique le rayon', (tester) async {
    final app = await buildTestApp(
      api: FakeApi((m, uri) {
        if (uri.path == '/alarms') return <Object>[];
        if (uri.path == '/config') {
          return {
            'alarm_radius_meters': 150,
            'alarm_poll_seconds': 600,
            'location_interval_seconds': 120,
          };
        }
        return null;
      }),
    );
    await pumpPhone(tester, app.page(const AlarmsPage()));

    expect(find.text('Rien pour le moment'), findsOneWidget);
    expect(find.textContaining('moins de 150 m'), findsOneWidget);
  });
}
