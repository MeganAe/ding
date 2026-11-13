import 'dart:async';
import 'dart:collection';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';

import '../../core/location_service.dart';
import '../../core/providers.dart';
import '../../core/theme.dart';
import '../../data/api_client.dart';
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

  /// Le dialogue « les conditions ont changé » n'est proposé qu'une fois par
  /// session : le répéter à chaque image serait du harcèlement.
  bool _termsProposed = false;

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

  /// Les conditions stockées sur le compte ne sont plus celles du serveur.
  void _maybeAskTerms(Profile? me, ServerConfig? config) {
    if (_termsProposed || me == null || config == null) return;
    if (me.termsVersion == null || config.termsVersion == null) return;
    if (me.termsVersion == config.termsVersion) return;

    _termsProposed = true;
    WidgetsBinding.instance.addPostFrameCallback((_) => _askTerms(config));
  }

  Future<void> _askTerms(ServerConfig config) async {
    if (!mounted) return;
    final choix = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Les conditions ont changé'),
        content: Text(
          'Une nouvelle version des conditions d’utilisation est en ligne '
          '(${config.termsVersion}). Tu peux la relire avant de l’accepter : '
          'l’app reste utilisable en attendant.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop('relire'),
            child: const Text('Relire'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop('plus_tard'),
            child: const Text('Plus tard'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop('accepter'),
            child: const Text('J’accepte'),
          ),
        ],
      ),
    );

    if (!mounted) return;
    if (choix == 'relire') {
      // On laisse le dialogue se reproposer au retour de la lecture.
      _termsProposed = false;
      await context.push('/legal/terms');
      return;
    }
    if (choix != 'accepter') return;

    try {
      await ref.read(repositoryProvider).acceptTerms();
      ref.invalidate(myProfileProvider);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Conditions acceptées.')),
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.message)));
    }
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

    final me = ref.watch(myProfileProvider).valueOrNull;
    _maybeAskTerms(me, ref.watch(serverConfigProvider).valueOrNull);
    final emailATConfirmer = me != null && !me.emailVerified;

    return Scaffold(
      body: Column(
        children: [
          if (emailATConfirmer)
            _NoticeBar(
              icon: Icons.mark_email_unread_outlined,
              text: 'Confirme ton adresse email : tant que ce n’est pas fait, '
                  'l’alarme ne sonne pas.',
              actionLabel: 'Vérifier',
              onAction: () => context.push('/verify'),
            ),
          if (showBanner)
            _NoticeBar(
              icon: Icons.location_off_outlined,
              text: switch (location) {
                LocationStatus.off =>
                  "Le GPS est coupé : l'alarme ne peut pas sonner.",
                LocationStatus.denied =>
                  "Sans accès à ta position, l'alarme ne peut pas sonner.",
                _ => "L'alarme ne sonne que si Ding est ouvert. Autorise "
                    '« Toujours » pour qu’elle sonne aussi écran éteint.',
              },
              actionLabel: switch (location) {
                LocationStatus.off => 'Activer',
                LocationStatus.denied => 'Autoriser',
                _ => 'Réglages',
              },
              onAction: () => _openSettings(location),
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

/// Une barre d'alerte en haut de l'écran : icône, une phrase, une action.
/// Sert au GPS coupé, à la permission manquante et à l'email à confirmer.
class _NoticeBar extends StatelessWidget {
  const _NoticeBar({
    required this.icon,
    required this.text,
    required this.actionLabel,
    required this.onAction,
    this.onDismiss,
  });

  final IconData icon;
  final String text;
  final String actionLabel;
  final VoidCallback onAction;

  /// Non nul quand le rappel n'est pas bloquant : l'utilisateur peut le
  /// repousser.
  final VoidCallback? onDismiss;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;

    return Material(
      color: DingColors.mist,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
          child: Row(
            children: [
              Icon(icon, size: 20, color: DingColors.ink),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  text,
                  style: theme.bodySmall?.copyWith(color: DingColors.ink),
                ),
              ),
              TextButton(onPressed: onAction, child: Text(actionLabel)),
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
