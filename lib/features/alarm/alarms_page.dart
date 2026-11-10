import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config.dart';
import '../../core/providers.dart';
import '../../data/api_client.dart';

String _two(int n) => n.toString().padLeft(2, '0');

/// « Aujourd'hui à 14:32 », « Hier à 09:05 », « Le 12/03 à 18:40 ».
String _format(DateTime d) {
  final l = d.toLocal();
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(l.year, l.month, l.day);
  final heure = '${_two(l.hour)}:${_two(l.minute)}';

  final ecart = today.difference(day).inDays;
  if (ecart == 0) return "Aujourd'hui à $heure";
  if (ecart == 1) return 'Hier à $heure';
  return 'Le ${_two(l.day)}/${_two(l.month)} à $heure';
}

class AlarmsPage extends ConsumerWidget {
  const AlarmsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context).textTheme;
    final alarms = ref.watch(alarmsProvider);

    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
            child: Text('Alarmes', style: theme.headlineMedium),
          ),
          Expanded(
            child: alarms.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, __) => Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        e is ApiException
                            ? e.message
                            : 'Impossible de charger tes alarmes.',
                        textAlign: TextAlign.center,
                        style: theme.bodyMedium,
                      ),
                      const SizedBox(height: 12),
                      OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size(140, 44),
                        ),
                        onPressed: () => ref.invalidate(alarmsProvider),
                        child: const Text('Réessayer'),
                      ),
                    ],
                  ),
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
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      children: [
                        Text(
                          "Aucune alarme pour l'instant. Elle sonne quand "
                          "quelqu'un que tu as choisi t'a aussi choisi et se "
                          'trouve à moins de ${Config.alarmRadiusMeters} m.',
                          style: theme.bodyLarge,
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
                  child: ListView.builder(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    itemCount: list.length,
                    itemBuilder: (_, i) {
                      final a = list[i];
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(a.otherName, style: theme.titleMedium),
                            Text(
                              [
                                _format(a.createdAt),
                                if (a.otherFaculty != null &&
                                    a.otherFaculty!.isNotEmpty)
                                  a.otherFaculty!,
                              ].join(', '),
                              style: theme.bodySmall,
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
