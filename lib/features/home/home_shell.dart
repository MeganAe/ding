import 'dart:async';
import 'dart:collection';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';

import '../../core/location_service.dart';
import '../../core/providers.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../alarm/alarms_page.dart';
import '../discover/discover_page.dart';
import '../profile/profile_page.dart';

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

  /// Incrémenté à chaque visite de l'onglet « Alarmes » : la page est
  /// reconstruite, ce qui remet à zéro les badges « Nouveau » et le compteur
  /// de la barre du bas, et relit la date de dernière visite.
  int _alarmsEpoch = 0;

  /// Alarmes en attente d'être montrées : si trois arrivent en même temps,
  /// on les présente l'une après l'autre au lieu d'en perdre deux.
  final Queue<AlarmItem> _queue = Queue<AlarmItem>();

  bool _ringOpen = false;

  /// true dès la première liste reçue : sert à mémoriser les alarmes
  /// existantes sans les faire sonner au démarrage.
  bool _firstSyncDone = false;

  /// L'utilisateur a repoussé le rappel « autorise Toujours » : on ne le
  /// répète pas à chaque retour dans l'app.
  bool _hideBackgroundHint = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    // Le système a pu arrêter le suivi : on le relance (start() est idempotent)
    // et on redemande les alarmes tout de suite, sans attendre le cycle.
    unawaited(ref.read(locationServiceProvider.notifier).start());
    ref.invalidate(alarmsProvider);
  }

  Future<void> _openSettings(LocationStatus status) async {
    if (status == LocationStatus.off) {
      await Geolocator.openLocationSettings();
    } else {
      await Geolocator.openAppSettings();
    }
    // Au retour des réglages, on réessaie : la permission vient peut-être
    // d'être accordée.
    unawaited(ref.read(locationServiceProvider.notifier).restart());
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

    // Lire le service suffit à le démarrer (voir locationServiceProvider).
    final location = ref.watch(locationServiceProvider);
    final showBanner = switch (location) {
      LocationStatus.off => true,
      LocationStatus.denied => true,
      LocationStatus.foregroundOnly => !_hideBackgroundHint,
      _ => false,
    };

    return Scaffold(
      body: Column(
        children: [
          if (showBanner)
            _LocationBanner(
              status: location,
              onOpenSettings: () => _openSettings(location),
              onDismiss: location == LocationStatus.foregroundOnly
                  ? () => setState(() => _hideBackgroundHint = true)
                  : null,
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
                  AlarmsPage(key: ValueKey('alarmes-$_alarmsEpoch'))
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
          if (i == 1) _alarmsEpoch++;
        }),
        destinations: [
          const NavigationDestination(
            icon: Icon(Icons.favorite_border),
            selectedIcon: Icon(Icons.favorite),
            label: 'Découvrir',
          ),
          NavigationDestination(
            icon: _AlarmBell(
              count: ref.watch(newAlarmsCountProvider),
              selected: false,
            ),
            selectedIcon: _AlarmBell(
              count: ref.watch(newAlarmsCountProvider),
              selected: true,
            ),
            label: 'Alarmes',
          ),
          const NavigationDestination(
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
  const _LocationBanner({
    required this.status,
    required this.onOpenSettings,
    this.onDismiss,
  });

  final LocationStatus status;
  final VoidCallback onOpenSettings;

  /// Non nul seulement quand le rappel n'est pas bloquant (permission
  /// « pendant l'usage ») : l'utilisateur peut le repousser.
  final VoidCallback? onDismiss;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;

    final (String texte, String action) = switch (status) {
      LocationStatus.off => (
          "Le GPS est coupé : l'alarme ne peut pas sonner.",
          'Activer',
        ),
      LocationStatus.denied => (
          "Sans accès à ta position, l'alarme ne peut pas sonner.",
          'Autoriser',
        ),
      _ => (
          "L'alarme ne sonne que si Ding est ouvert. Autorise « Toujours » "
          'pour qu’elle sonne aussi écran éteint.',
          'Réglages',
        ),
    };

    return Material(
      color: DingColors.mist,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
          child: Row(
            children: [
              const Icon(
                Icons.location_off_outlined,
                size: 20,
                color: DingColors.ink,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  texte,
                  style: theme.bodySmall?.copyWith(color: DingColors.ink),
                ),
              ),
              TextButton(onPressed: onOpenSettings, child: Text(action)),
              if (onDismiss != null)
                IconButton(
                  tooltip: 'Plus tard',
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.close, size: 18),
                  color: DingColors.slate,
                  onPressed: onDismiss,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// La cloche, avec le nombre d'alarmes reçues depuis la dernière visite.
class _AlarmBell extends StatelessWidget {
  const _AlarmBell({required this.count, required this.selected});

  final int count;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final icon =
        Icon(selected ? Icons.notifications : Icons.notifications_none);
    if (count <= 0) return icon;
    return Badge(
      label: Text(count > 9 ? '9+' : '$count'),
      child: icon,
    );
  }
}
