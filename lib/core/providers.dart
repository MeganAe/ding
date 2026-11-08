import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/models.dart';
import '../data/repository.dart';

final prefsProvider = Provider<SharedPreferences>(
  (ref) => throw UnimplementedError('Défini dans main()'),
);

final supabaseProvider =
    Provider<SupabaseClient>((ref) => Supabase.instance.client);

final repositoryProvider =
    Provider<Repository>((ref) => Repository(ref.watch(supabaseProvider)));

final sessionProvider = StreamProvider<Session?>((ref) async* {
  final auth = ref.watch(supabaseProvider).auth;
  yield auth.currentSession;
  await for (final change in auth.onAuthStateChange) {
    yield change.session;
  }
});

final onboardingDoneProvider = StateProvider<bool>(
  (ref) => ref.read(prefsProvider).getBool('onboarding_done') ?? false,
);

final profilesProvider = FutureProvider.autoDispose<List<Profile>>(
  (ref) => ref.watch(repositoryProvider).campus(),
);

final crushesProvider = FutureProvider.autoDispose<Set<String>>(
  (ref) => ref.watch(repositoryProvider).myCrushes(),
);

final myProfileProvider = FutureProvider.autoDispose<Profile?>(
  (ref) => ref.watch(repositoryProvider).me(),
);

/// Se met à jour en direct dès qu'une alarme est créée pour moi.
final alarmsProvider = StreamProvider.autoDispose<List<AlarmItem>>((ref) async* {
  final repo = ref.watch(repositoryProvider);
  final client = ref.watch(supabaseProvider);
  yield await repo.myAlarms();
  await for (final _ in client.from('alarms').stream(primaryKey: ['id'])) {
    yield await repo.myAlarms();
  }
});

/// Alarmes déjà présentées, pour ne faire sonner que les nouvelles.
final seenAlarmsProvider = StateProvider<Set<String>>((ref) => <String>{});
