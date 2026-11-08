import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../core/theme.dart';
import '../../data/models.dart';

class DiscoverPage extends ConsumerStatefulWidget {
  const DiscoverPage({super.key});

  @override
  ConsumerState<DiscoverPage> createState() => _DiscoverPageState();
}

class _DiscoverPageState extends ConsumerState<DiscoverPage> {
  String _query = '';

  Future<void> _toggle(Profile p) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final active = await ref.read(repositoryProvider).toggleCrush(p.id);
      ref.invalidate(crushesProvider);
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(SnackBar(
        content: Text(active
            ? "Enregistré. Personne n'est prévenu."
            : 'Choix retiré.'),
      ));
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Action impossible. Réessaie.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    final profiles = ref.watch(profilesProvider);
    final crushes = ref.watch(crushesProvider).valueOrNull ?? <String>{};

    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 4),
            child: Text('Choisis en secret', style: theme.headlineMedium),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Text(
              "Personne n'est prévenu de ton choix.",
              style: theme.bodySmall,
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
            child: TextField(
              onChanged: (v) => setState(() => _query = v.trim().toLowerCase()),
              decoration: const InputDecoration(
                hintText: 'Rechercher un prénom',
                prefixIcon: Icon(Icons.search),
              ),
            ),
          ),
          Expanded(
            child: profiles.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (_, __) => Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('Impossible de charger le campus.'),
                      const SizedBox(height: 12),
                      OutlinedButton(
                        style: OutlinedButton.styleFrom(
                            minimumSize: const Size(140, 44)),
                        onPressed: () => ref.invalidate(profilesProvider),
                        child: const Text('Réessayer'),
                      ),
                    ],
                  ),
                ),
              ),
              data: (all) {
                final list = all
                    .where((p) => p.firstName.toLowerCase().contains(_query))
                    .toList();
                if (list.isEmpty) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        all.isEmpty
                            ? "Personne d'autre n'est inscrit pour l'instant. Invite tes amis."
                            : 'Aucun prénom ne correspond.',
                        textAlign: TextAlign.center,
                        style: theme.bodyMedium,
                      ),
                    ),
                  );
                }
                return ListView.builder(
                  padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
                  itemCount: list.length,
                  itemBuilder: (_, i) {
                    final p = list[i];
                    final chosen = crushes.contains(p.id);
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Row(
                        children: [
                          CircleAvatar(
                            radius: 24,
                            backgroundColor: DingColors.mist,
                            foregroundColor: DingColors.ink,
                            child: Text(p.initial, style: theme.titleMedium),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(p.firstName, style: theme.titleMedium),
                                if (p.detail.isNotEmpty)
                                  Text(p.detail, style: theme.bodySmall),
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),
                          SizedBox(
                            width: 104,
                            child: chosen
                                ? FilledButton(
                                    style: FilledButton.styleFrom(
                                        minimumSize: const Size(104, 40)),
                                    onPressed: () => _toggle(p),
                                    child: const Text('Choisi'),
                                  )
                                : OutlinedButton(
                                    style: OutlinedButton.styleFrom(
                                        minimumSize: const Size(104, 40)),
                                    onPressed: () => _toggle(p),
                                    child: const Text('Choisir'),
                                  ),
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
