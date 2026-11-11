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

/// L'annuaire : une page à la fois, avec la recherche et le défilement infini.
class CampusState {
  const CampusState({
    required this.items,
    required this.total,
    this.nextOffset,
    this.query = '',
  });

  final List<Profile> items;

  /// Total côté serveur (pas seulement ce qui est chargé).
  final int total;
  final int? nextOffset;
  final String query;

  bool get hasMore => nextOffset != null;
}

class CampusNotifier extends AsyncNotifier<CampusState> {
  @override
  Future<CampusState> build() => _fetch('');

  Future<CampusState> _fetch(String query) async {
    final page = await ref.read(repositoryProvider).campus(query: query);
    return CampusState(
      items: page.items,
      total: page.total,
      nextOffset: page.nextOffset,
      query: query,
    );
  }

  /// Nouvelle recherche (ou retour à la liste complète si [query] est vide).
  Future<void> search(String query) async {
    final q = query.trim();
    if (state.hasValue && state.value!.query == q) return;
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() => _fetch(q));
  }

  /// Page suivante, ajoutée à la suite. En cas d'échec réseau on garde la
  /// liste déjà affichée : mieux vaut une liste incomplète qu'un écran vide.
  Future<void> loadMore() async {
    final current = state.valueOrNull;
    if (current == null || current.nextOffset == null) return;

    try {
      final page = await ref.read(repositoryProvider).campus(
            query: current.query,
            offset: current.nextOffset!,
          );
      final known = current.items.map((p) => p.id).toSet();
      state = AsyncValue.data(CampusState(
        items: [
          ...current.items,
          ...page.items.where((p) => !known.contains(p.id)),
        ],
        total: page.total,
        nextOffset: page.nextOffset,
        query: current.query,
      ));
    } on ApiException {
      // Silencieux : le prochain défilement réessaiera.
    }
  }

  Future<void> refresh() async {
    final q = state.valueOrNull?.query ?? '';
    state = await AsyncValue.guard(() => _fetch(q));
  }
}

final campusProvider =
    AsyncNotifierProvider<CampusNotifier, CampusState>(CampusNotifier.new);

/// Les personnes que j'ai bloquées (écran Profil : liste + déblocage).
final blockedProvider = FutureProvider<List<Profile>>(
  (ref) => ref.watch(repositoryProvider).blocked(),
);

/// Leurs identifiants, pour griser un bouton ou filtrer localement.
final blockedIdsProvider = Provider<Set<String>>(
  (ref) => {
    for (final p in ref.watch(blockedProvider).valueOrNull ?? const <Profile>[])
      p.id,
  },
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

/// Réglages publics de l'API : le rayon d'alarme et les intervalles viennent
/// du serveur, plus d'une constante recopiée dans l'app.
final serverConfigProvider = FutureProvider<ServerConfig?>(
  (ref) => ref.watch(repositoryProvider).config(),
);

final alarmRadiusProvider = Provider<int>((ref) =>
    ref.watch(serverConfigProvider).valueOrNull?.alarmRadiusMeters ??
    Config.alarmRadiusMeters);

/// Alarmes reçues depuis la dernière visite de l'onglet « Alarmes » : c'est le
/// point rouge de la barre du bas. Distinct de `seenAlarms` (qui sert à ne pas
/// faire sonner deux fois la même alarme) : on peut avoir vu l'alarme sonner
/// et ne pas encore avoir ouvert la liste.
class LastAlarmsVisit extends StateNotifier<DateTime> {
  LastAlarmsVisit(this._prefs)
      : super(DateTime.fromMillisecondsSinceEpoch(
          _prefs.getInt(_key) ?? 0,
        ));

  static const _key = 'last_alarms_visit';
  final SharedPreferences _prefs;

  void mark() {
    final now = DateTime.now();
    state = now;
    unawaited(_prefs.setInt(_key, now.millisecondsSinceEpoch));
  }
}

final lastAlarmsVisitProvider =
    StateNotifierProvider<LastAlarmsVisit, DateTime>(
  (ref) => LastAlarmsVisit(ref.watch(prefsProvider)),
);

final newAlarmsCountProvider = Provider<int>((ref) {
  final alarms = ref.watch(alarmsProvider).valueOrNull;
  if (alarms == null) return 0;
  final since = ref.watch(lastAlarmsVisitProvider);
  return alarms.where((a) => a.createdAt.isAfter(since)).length;
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
