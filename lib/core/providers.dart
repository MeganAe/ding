import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/api_client.dart';
import '../data/models.dart';
import '../data/repository.dart';
import '../data/token_store.dart';
import 'config.dart';

final prefsProvider = Provider<SharedPreferences>(
  (ref) => throw UnimplementedError('Défini dans main()'),
);

final tokenStoreProvider = Provider<TokenStore>(
  (ref) => throw UnimplementedError('Défini dans main()'),
);

final apiClientProvider = Provider<ApiClient>((ref) {
  final api = ApiClient(ref.watch(tokenStoreProvider));
  ref.onDispose(api.dispose);
  return api;
});

final repositoryProvider =
    Provider<Repository>((ref) => Repository(ref.watch(apiClientProvider)));

/// true quand l'utilisateur est connecté, false sinon.
final sessionProvider = StreamProvider<bool>((ref) async* {
  final api = ref.watch(apiClientProvider);
  yield api.loggedIn;
  yield* api.authChanges;
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

/// Interroge l'API régulièrement pour détecter les nouvelles alarmes.
/// (Pas de temps réel : on fait du polling, voir README § limites connues.)
final alarmsProvider = FutureProvider.autoDispose<List<AlarmItem>>((ref) async {
  final timer = Timer(Config.alarmPollInterval, ref.invalidateSelf);
  ref.onDispose(timer.cancel);
  return ref.watch(repositoryProvider).myAlarms();
});

/// Alarmes déjà présentées, pour ne faire sonner que les nouvelles.
///
/// Persistées : sans ça, une alarme déjà vue rejouait après un redémarrage
/// (et le garde-fou « premier chargement » masquait les vraies nouvelles
/// alarmes après une coupure réseau).
class SeenAlarms extends StateNotifier<Set<String>> {
  SeenAlarms(this._prefs) : super(_read(_prefs));

  static const _key = 'seen_alarms';
  static const _max = 200;

  final SharedPreferences _prefs;

  static Set<String> _read(SharedPreferences p) =>
      (p.getStringList(_key) ?? const <String>[]).toSet();

  void addAll(Iterable<String> ids) {
    final next = {...state, ...ids};
    final trimmed =
        next.length > _max ? next.skip(next.length - _max).toSet() : next;
    state = trimmed;
    unawaited(_prefs.setStringList(_key, trimmed.toList()));
  }
}

final seenAlarmsProvider =
    StateNotifierProvider<SeenAlarms, Set<String>>((ref) {
  return SeenAlarms(ref.watch(prefsProvider));
});
