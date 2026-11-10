import 'dart:async';
import 'dart:collection';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';

import '../../core/config.dart';
import '../../core/providers.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../alarm/alarms_page.dart';
import '../discover/discover_page.dart';
import '../profile/profile_page.dart';

/// Ce qui empêche l'envoi de la position, s'il y a lieu.
enum _LocProblem { none, service, permission }

class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key});

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell>
    with WidgetsBindingObserver {
  int _tab = 0;

  /// Onglets déjà construits : l'annuaire n'est chargé qu'au premier affichage
  /// de son onglet, pas au démarrage de l'app.
  final Set<int> _built = {0};

  Timer? _timer;
  _LocProblem _locProblem = _LocProblem.none;

  /// Alarmes en attente d'être montrées : si trois arrivent en même temps,
  /// on les présente l'une après l'autre au lieu d'en perdre deux.
  final Queue<AlarmItem> _queue = Queue<AlarmItem>();

  bool _ringOpen = false;

  /// true dès la première liste reçue : sert à mémoriser les alarmes
  /// existantes sans les faire sonner au démarrage.
  bool _firstSyncDone = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _sendLocation();
    _startTimer();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    super.dispose();
  }

  /// L'appli ne suit la position que lorsqu'elle est au premier plan :
  /// on coupe le minuteur en arrière-plan (batterie, données) et on repart
  /// immédiatement au retour, pour ne pas rater une alarme.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _sendLocation();
      _startTimer();
      ref.invalidate(alarmsProvider);
    } else {
      _timer?.cancel();
      _timer = null;
    }
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(Config.locationInterval, (_) => _sendLocation());
  }

  void _setProblem(_LocProblem p) {
    if (!mounted || _locProblem == p) return;
    setState(() => _locProblem = p);
  }

  /// V1 : la position est envoyée uniquement quand l'appli est ouverte.
  Future<void> _sendLocation() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        _setProblem(_LocProblem.service);
        return;
      }

      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        _setProblem(_LocProblem.permission);
        return;
      }

      // Précision haute : avec `medium` l'erreur de mesure (~100 m) est du
      // même ordre que le rayon de l'alarme (150 m), ce qui fait sonner à
      // tort ou pas du tout.
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 25),
        ),
      );
      if (!mounted) return;
      _setProblem(_LocProblem.none);
      await ref.read(repositoryProvider).sendLocation(
            pos.latitude,
            pos.longitude,
          );
    } catch (_) {
      // GPS, timeout ou réseau : on réessaiera au prochain cycle.
    }
  }

  Future<void> _openSettings() async {
    if (_locProblem == _LocProblem.service) {
      await Geolocator.openLocationSettings();
    } else {
      await Geolocator.openAppSettings();
    }
  }

  /// Traite chaque nouvelle liste d'alarmes et alimente la file d'attente.
  void _onAlarms(List<AlarmItem> list) {
    final seen = ref.read(seenAlarmsProvider);

    if (!_firstSyncDone) {
      _firstSyncDone = true;
      ref.read(seenAlarmsProvider.notifier).addAll(list.map((a) => a.id));
      return;
    }

    final fresh = list.where((a) => !seen.contains(a.id)).toList();
    if (fresh.isEmpty) return;

    ref.read(seenAlarmsProvider.notifier).addAll(fresh.map((a) => a.id));
    _queue.addAll(fresh);
    unawaited(_showNextAlarm());
  }

  Future<void> _showNextAlarm() async {
    if (_ringOpen || _queue.isEmpty || !mounted) return;
    _ringOpen = true;
    final alarm = _queue.removeFirst();
    await context.push('/ring', extra: alarm);
    _ringOpen = false;
    if (mounted) unawaited(_showNextAlarm());
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(alarmsProvider, (prev, next) {
      final list = next.valueOrNull;
      if (list != null) _onAlarms(list);
    });

    return Scaffold(
      body: Column(
        children: [
          if (_locProblem != _LocProblem.none) _LocationBanner(
            problem: _locProblem,
            onOpenSettings: _openSettings,
          ),
          Expanded(
            child: IndexedStack(
              index: _tab,
              children: [
                if (_built.contains(0))
                  const DiscoverPage()
                else
                  const SizedBox.shrink(),
                if (_built.contains(1))
                  const AlarmsPage()
                else
                  const SizedBox.shrink(),
                if (_built.contains(2))
                  const ProfilePage()
                else
                  const SizedBox.shrink(),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() {
          _tab = i;
          _built.add(i);
        }),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.favorite_border),
            selectedIcon: Icon(Icons.favorite),
            label: 'Découvrir',
          ),
          NavigationDestination(
            icon: Icon(Icons.notifications_none),
            selectedIcon: Icon(Icons.notifications),
            label: 'Alarmes',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person),
            label: 'Profil',
          ),
        ],
      ),
    );
  }
}

/// Sans position, l'alarme ne peut pas sonner : l'utilisateur doit le savoir,
/// avec un moyen d'aller corriger le réglage.
class _LocationBanner extends StatelessWidget {
  const _LocationBanner({required this.problem, required this.onOpenSettings});

  final _LocProblem problem;
  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    final isService = problem == _LocProblem.service;

    return Material(
      color: DingColors.mist,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
          child: Row(
            children: [
              const Icon(Icons.location_off_outlined,
                  size: 20, color: DingColors.ink),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  isService
                      ? 'Le GPS est coupé : l\'alarme ne peut pas sonner.'
                      : 'Sans accès à ta position, l\'alarme ne peut pas sonner.',
                  style: theme.bodySmall?.copyWith(color: DingColors.ink),
                ),
              ),
              TextButton(
                onPressed: onOpenSettings,
                child: Text(isService ? 'Activer' : 'Autoriser'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
