import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config.dart';
import '../../core/providers.dart';

String _two(int n) => n.toString().padLeft(2, '0');

String _format(DateTime d) {
  final l = d.toLocal();
  return 'Le ${_two(l.day)}/${_two(l.month)} à ${_two(l.hour)}:${_two(l.minute)}';
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
              error: (_, __) =>
                  const Center(child: Text('Impossible de charger tes alarmes.')),
              data: (list) {
                if (list.isEmpty) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Text(
                      "Aucune alarme pour l'instant. Elle sonne quand quelqu'un que tu as choisi t'a aussi choisi et se trouve à moins de ${Config.alarmRadiusMeters} m.",
                      style: theme.bodyLarge,
                    ),
                  );
                }
                return ListView.builder(
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
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
