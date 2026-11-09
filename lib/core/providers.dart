import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/api_client.dart';
import '../data/models.dart';
import '../data/repository.dart';

final prefsProvider = Provider<SharedPreferences>(
  (ref) => throw UnimplementedError('Défini dans main()'),
);

final apiClientProvider =
    Provider<ApiClient>((ref) => ApiClient(ref.watch(prefsProvider)));

final repositoryProvider =
    Provider<Repository>((ref) => Repository(ref.watch(apiClientProvider)));

/// true quand l'utilisateur est connecté, false sinon.
final sessionProvider = StreamProvider<bool>((ref) async* {
  final api = ref.watch(apiClientProvider);
  yield api.loggedIn;
  await for (final loggedIn in api.authChanges) {
    yield loggedIn;
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

/// Interroge l'API toutes les 20 secondes pour détecter les nouvelles alarmes.
/// (Le temps réel de Supabase n'existe plus : on fait du polling.)
final alarmsProvider = FutureProvider.autoDispose<List<AlarmItem>>((ref) async {
  final timer = Timer(const Duration(seconds: 20), ref.invalidateSelf);
  ref.onDispose(timer.cancel);
  return ref.watch(repositoryProvider).myAlarms();
});

/// Alarmes déjà présentées, pour ne faire sonner que les nouvelles.
final seenAlarmsProvider = StateProvider<Set<String>>((ref) => <String>{});
