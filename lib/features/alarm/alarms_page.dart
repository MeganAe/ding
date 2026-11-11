import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers.dart';
import '../../core/theme.dart';
import '../../core/widgets/empty_state.dart';
import '../../core/widgets/initials_avatar.dart';
import '../../data/api_client.dart';
import '../../data/models.dart';

String _two(int n) => n.toString().padLeft(2, '0');

const _mois = [
  'janvier',
  'février',
  'mars',
  'avril',
  'mai',
  'juin',
  'juillet',
  'août',
  'septembre',
  'octobre',
  'novembre',
  'décembre',
];

String _heure(DateTime d) {
  final l = d.toLocal();
  return '${_two(l.hour)}:${_two(l.minute)}';
}

/// « Aujourd'hui », « Hier », « 12 mars ».
String _jour(DateTime d) {
  final l = d.toLocal();
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(l.year, l.month, l.day);
  final ecart = today.difference(day).inDays;
  if (ecart == 0) return "Aujourd'hui";
  if (ecart == 1) return 'Hier';
  if (l.year == now.year) return '${l.day} ${_mois[l.month - 1]}';
  return '${l.day} ${_mois[l.month - 1]} ${l.year}';
}

/// « il y a 4 min », « il y a 2 h » — seulement pour aujourd'hui.
String? _ilYA(DateTime d) {
  final l = d.toLocal();
  if (l.day != DateTime.now().day) return null;
  final diff = DateTime.now().difference(l);
  if (diff.inMinutes < 1) return "à l'instant";
  if (diff.inMinutes < 60) return 'il y a ${diff.inMinutes} min';
  return 'il y a ${diff.inHours} h';
}

class AlarmsPage extends ConsumerStatefulWidget {
  const AlarmsPage({super.key});

  @override
  ConsumerState<AlarmsPage> createState() => _AlarmsPageState();
}

class _AlarmsPageState extends ConsumerState<AlarmsPage> {
  /// Instant de la dernière visite, capturé à l'ouverture : sert à marquer les
  /// alarmes « nouvelles » le temps de cette visite, puis le compteur de la
  /// barre du bas repart à zéro.
  late final DateTime _since;
  bool _marked = false;

  @override
  void initState() {
    super.initState();
    _since = ref.read(lastAlarmsVisitProvider);
  }

  void _markVisited() {
    if (_marked) return;
    _marked = true;
    ref.read(lastAlarmsVisitProvider.notifier).mark();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    final alarms = ref.watch(alarmsProvider);
    final radius = ref.watch(alarmRadiusProvider);

    // Le marquage se fait après la première image : sinon le badge
    // disparaîtrait avant qu'on ait vu de quoi il parlait.
    WidgetsBinding.instance.addPostFrameCallback((_) => _markVisited());

    return SafeArea(
      bottom: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
            child: Text('Alarmes', style: theme.headlineMedium),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 6, 24, 0),
            child: Text(
              "Chaque ligne est quelqu'un qui t'a choisi aussi.",
              style: theme.bodySmall,
            ),
          ),
          Expanded(
            child: alarms.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, __) => EmptyState(
                icon: Icons.cloud_off_outlined,
                title: 'Alarmes indisponibles',
                body: e is ApiException
                    ? e.message
                    : 'Impossible de charger tes alarmes.',
                action: OutlinedButton(
                  onPressed: () => ref.invalidate(alarmsProvider),
                  child: const Text('Réessayer'),
                ),
              ),
              data: (list) {
                if (list.isEmpty) {
                  return RefreshIndicator(
                    onRefresh: () async {
                      ref.invalidate(alarmsProvider);
                      await ref.read(alarmsProvider.future);
                    },
                    child: ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      children: [
                        EmptyState(
                          icon: Icons.notifications_none,
                          title: 'Rien pour le moment',
                          body: "Elle sonne quand quelqu'un que tu as choisi "
                              "t'a choisi aussi, et se trouve à moins de "
                              '$radius m de toi.',
                        ),
                      ],
                    ),
                  );
                }

                return RefreshIndicator(
                  onRefresh: () async {
                    ref.invalidate(alarmsProvider);
                    await ref.read(alarmsProvider.future);
                  },
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
                    children: _grouped(list),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  /// Une section par jour, de la plus récente à la plus ancienne.
  List<Widget> _grouped(List<AlarmItem> alarms) {
    final theme = Theme.of(context).textTheme;
    final children = <Widget>[];
    String? jourCourant;

    for (final a in alarms) {
      final jour = _jour(a.createdAt);
      if (jour != jourCourant) {
        jourCourant = jour;
        children.add(Padding(
          padding: EdgeInsets.only(top: children.isEmpty ? 0 : 20, bottom: 8),
          child: Text(
            jour,
            style: theme.bodySmall?.copyWith(
              letterSpacing: 0.6,
              fontWeight: FontWeight.w600,
              color: DingColors.ink,
            ),
          ),
        ));
      }

      final nouveau = a.createdAt.isAfter(_since);
      children.add(Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: _AlarmCard(
          alarm: a,
          nouveau: nouveau,
          onTap: () => context.push('/ring', extra: a),
        ),
      ));
    }
    return children;
  }
}

class _AlarmCard extends StatelessWidget {
  const _AlarmCard({
    required this.alarm,
    required this.nouveau,
    required this.onTap,
  });

  final AlarmItem alarm;
  final bool nouveau;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    final relatif = _ilYA(alarm.createdAt);

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
          child: Row(
            children: [
              InitialsAvatar(name: alarm.otherName, radius: 22),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            alarm.otherName.isEmpty
                                ? 'Quelqu’un'
                                : alarm.otherName,
                            style: theme.titleMedium,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (nouveau) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: DingColors.signal,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              'Nouveau',
                              style: theme.bodySmall?.copyWith(
                                color: DingColors.paper,
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      [
                        _heure(alarm.createdAt),
                        if (relatif != null) relatif,
                        if (alarm.otherFaculty != null &&
                            alarm.otherFaculty!.isNotEmpty)
                          alarm.otherFaculty!,
                      ].join(' · '),
                      style: theme.bodySmall,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.chevron_right,
                color: DingColors.slate,
                size: 20,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
