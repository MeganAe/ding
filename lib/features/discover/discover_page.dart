import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../core/theme.dart';
import '../../data/api_client.dart';
import '../../data/models.dart';

class DiscoverPage extends ConsumerStatefulWidget {
  const DiscoverPage({super.key});

  @override
  ConsumerState<DiscoverPage> createState() => _DiscoverPageState();
}

class _DiscoverPageState extends ConsumerState<DiscoverPage> {
  String _query = '';

  /// Copie locale optimiste des choix : le bouton réagit tout de suite et ne
  /// clignote pas (ni ne repasse à « Choisir ») pendant le rechargement de la
  /// liste renvoyée par le serveur.
  Set<String>? _chosen;

  /// Personnes dont une requête est en cours : évite les doubles envois.
  final _busy = <String>{};

  @override
  void initState() {
    super.initState();
    // Si la liste est déjà en cache, on part de là sans attendre un rebuild.
    final cached = ref.read(crushesProvider).valueOrNull;
    if (cached != null) _chosen = {...cached};

    // Resynchronise avec le serveur, sauf si des requêtes sont en vol.
    ref.listenManual(crushesProvider, (_, next) {
      final server = next.valueOrNull;
      if (server == null || _busy.isNotEmpty) return;
      setState(() => _chosen = {...server});
    });
  }

  Future<void> _setChoice(Profile p, {required bool active}) async {
    if (_busy.contains(p.id)) return;
    final messenger = ScaffoldMessenger.of(context);
    final before = _chosen == null ? null : {..._chosen!};

    setState(() {
      _busy.add(p.id);
      final set = _chosen ??= <String>{};
      if (active) {
        set.add(p.id);
      } else {
        set.remove(p.id);
      }
    });

    try {
      await ref.read(repositoryProvider).setCrush(p.id, active: active);
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(SnackBar(
        content: Text(active
            ? "Enregistré. Personne n'est prévenu."
            : 'Choix retiré.'),
      ));
    } on ApiException catch (e) {
      if (mounted) setState(() => _chosen = before);
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      if (mounted) setState(() => _chosen = before);
      messenger.showSnackBar(
        const SnackBar(content: Text('Action impossible. Réessaie.')),
      );
    } finally {
      if (mounted) setState(() => _busy.remove(p.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    final profiles = ref.watch(profilesProvider);
    final server = ref.watch(crushesProvider).valueOrNull;
    if (server != null && _chosen == null) _chosen = {...server};
    final chosen = _chosen ?? const <String>{};

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
              error: (e, __) => Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        e is ApiException
                            ? e.message
                            : 'Impossible de charger le campus.',
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 12),
                      OutlinedButton(
                        style: OutlinedButton.styleFrom(
                            minimumSize: const Size(140, 44)),
                        onPressed: () {
                          ref.invalidate(profilesProvider);
                          ref.invalidate(crushesProvider);
                        },
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
                return RefreshIndicator(
                  onRefresh: () async {
                    ref.invalidate(profilesProvider);
                    ref.invalidate(crushesProvider);
                    await ref.read(profilesProvider.future);
                  },
                  child: ListView.builder(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
                    itemCount: list.length,
                    itemBuilder: (_, i) => _ProfileRow(
                      profile: list[i],
                      chosen: chosen.contains(list[i].id),
                      busy: _busy.contains(list[i].id),
                      onChanged: (active) =>
                          _setChoice(list[i], active: active),
                    ),
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

class _ProfileRow extends StatelessWidget {
  const _ProfileRow({
    required this.profile,
    required this.chosen,
    required this.busy,
    required this.onChanged,
  });

  final Profile profile;
  final bool chosen;
  final bool busy;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    const pill = Size(104, 40);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          CircleAvatar(
            radius: 24,
            backgroundColor: DingColors.mist,
            foregroundColor: DingColors.ink,
            child: Text(profile.initial, style: theme.titleMedium),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(profile.firstName, style: theme.titleMedium),
                if (profile.detail.isNotEmpty)
                  Text(profile.detail, style: theme.bodySmall),
              ],
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: pill.width,
            child: busy
                ? const SizedBox(
                    height: 40,
                    child: Center(
                      child: SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                  )
                : Semantics(
                    button: true,
                    selected: chosen,
                    label: chosen
                        ? '${profile.firstName} : choisi, appuyer pour retirer'
                        : 'Choisir ${profile.firstName}',
                    child: chosen
                        ? FilledButton(
                            style: FilledButton.styleFrom(minimumSize: pill),
                            onPressed: () => onChanged(false),
                            child: const Text('Choisi'),
                          )
                        : OutlinedButton(
                            style: OutlinedButton.styleFrom(minimumSize: pill),
                            onPressed: () => onChanged(true),
                            child: const Text('Choisir'),
                          ),
                  ),
          ),
        ],
      ),
    );
  }
}
