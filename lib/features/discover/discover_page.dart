import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../core/theme.dart';
import '../../core/widgets/empty_state.dart';
import '../../core/widgets/initials_avatar.dart';
import '../../data/api_client.dart';
import '../../data/models.dart';

/// L'annuaire du campus.
///
/// La recherche et la pagination se font côté serveur : l'ancienne version
/// chargeait les 500 premiers inscrits puis filtrait dans le téléphone.
class DiscoverPage extends ConsumerStatefulWidget {
  const DiscoverPage({super.key});

  @override
  ConsumerState<DiscoverPage> createState() => _DiscoverPageState();
}

class _DiscoverPageState extends ConsumerState<DiscoverPage> {
  final _search = TextEditingController();
  final _scroll = ScrollController();
  Timer? _debounce;
  bool _loadingMore = false;

  /// Copie locale optimiste des choix : le bouton réagit tout de suite et ne
  /// clignote pas pendant le rechargement de la liste.
  Set<String>? _chosen;

  /// Personnes dont une requête est en cours : évite les doubles envois.
  final _busy = <String>{};

  @override
  void initState() {
    super.initState();

    final cached = ref.read(crushesProvider).valueOrNull;
    if (cached != null) _chosen = {...cached};

    ref.listenManual(crushesProvider, (_, next) {
      final server = next.valueOrNull;
      if (server == null || _busy.isNotEmpty) return;
      setState(() => _chosen = {...server});
    });

    _scroll.addListener(_onScroll);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _scroll.dispose();
    _search.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_loadingMore || !_scroll.hasClients) return;
    if (_scroll.position.pixels < _scroll.position.maxScrollExtent - 400) return;
    final state = ref.read(campusProvider).valueOrNull;
    if (state == null || !state.hasMore) return;

    setState(() => _loadingMore = true);
    ref.read(campusProvider.notifier).loadMore().whenComplete(() {
      if (mounted) setState(() => _loadingMore = false);
    });
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 320), () {
      ref.read(campusProvider.notifier).search(value);
    });
  }

  void _clearSearch() {
    _debounce?.cancel();
    _search.clear();
    ref.read(campusProvider.notifier).search('');
    setState(() {});
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

  // ───────────── Bloquer / signaler ─────────────

  Future<void> _openActions(Profile p) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 4),
              child: Text(p.firstName, style: Theme.of(ctx).textTheme.titleLarge),
            ),
            ListTile(
              leading: const Icon(Icons.person_off_outlined),
              title: const Text('Bloquer'),
              subtitle: Text(
                '${p.firstName} disparaît de ton annuaire. Vos choix et vos '
                'alarmes sont effacés.',
              ),
              onTap: () => Navigator.of(ctx).pop('block'),
            ),
            ListTile(
              leading: const Icon(Icons.flag_outlined),
              title: const Text('Signaler'),
              subtitle: const Text(
                'Un comportement qui ne devrait pas exister sur le campus.',
              ),
              onTap: () => Navigator.of(ctx).pop('report'),
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );

    if (!mounted || action == null) return;
    if (action == 'block') {
      await _confirmBlock(p);
    } else {
      await _report(p);
    }
  }

  Future<void> _confirmBlock(Profile p) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Bloquer ${p.firstName} ?'),
        content: const Text(
          'Cette personne ne pourra plus apparaître dans ton annuaire, et '
          'aucune alarme ne sonnera entre vous. Tu pourras débloquer plus tard '
          'depuis ton profil.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Annuler'),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: DingColors.signal),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Bloquer'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(repositoryProvider).block(p.id);
      ref.invalidate(campusProvider);
      ref.invalidate(crushesProvider);
      ref.invalidate(blockedProvider);
      messenger.showSnackBar(SnackBar(
        content: Text('${p.firstName} est bloqué.'),
        action: SnackBarAction(
          label: 'Annuler',
          onPressed: () async {
            await ref.read(repositoryProvider).unblock(p.id);
            ref.invalidate(campusProvider);
            ref.invalidate(blockedProvider);
          },
        ),
      ));
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _report(Profile p) async {
    const motifs = {
      'harcelement': 'Harcèlement',
      'faux_profil': "Faux profil / usurpation d'identité",
      'intimidation': 'Propos intimidants',
      'autre': 'Autre chose',
    };

    final reason = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 4),
              child: Text(
                'Signaler ${p.firstName}',
                style: Theme.of(ctx).textTheme.titleLarge,
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
              child: Text(
                'Le signalement est confidentiel : personne sur le campus ne '
                'saura que tu l’as fait.',
                style: Theme.of(ctx).textTheme.bodySmall,
              ),
            ),
            for (final m in motifs.entries)
              ListTile(
                title: Text(m.value),
                onTap: () => Navigator.of(ctx).pop(m.key),
              ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );

    if (!mounted || reason == null) return;

    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(repositoryProvider).report(p.id, reason);
      messenger.showSnackBar(
        const SnackBar(content: Text('Signalement envoyé. Merci.')),
      );
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    final campus = ref.watch(campusProvider);
    final server = ref.watch(crushesProvider).valueOrNull;
    if (server != null && _chosen == null) _chosen = {...server};
    final chosen = _chosen ?? const <String>{};

    return SafeArea(
      bottom: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
            child: Text('Le campus', style: theme.headlineMedium),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 6, 24, 0),
            child: Text(
              "Choisis en secret. Personne n'est prévenu.",
              style: theme.bodySmall,
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
            child: TextField(
              controller: _search,
              onChanged: _onSearchChanged,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: 'Rechercher un prénom',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _search.text.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Effacer la recherche',
                        icon: const Icon(Icons.close),
                        onPressed: _clearSearch,
                      ),
              ),
            ),
          ),
          Expanded(
            child: campus.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, __) => EmptyState(
                icon: Icons.cloud_off_outlined,
                title: 'Annuaire inaccessible',
                body: e is ApiException
                    ? e.message
                    : 'Impossible de charger le campus.',
                action: OutlinedButton(
                  onPressed: () {
                    ref.invalidate(campusProvider);
                    ref.invalidate(crushesProvider);
                  },
                  child: const Text('Réessayer'),
                ),
              ),
              data: (state) {
                if (state.items.isEmpty) {
                  final cherche = state.query.isNotEmpty;
                  return EmptyState(
                    icon: cherche
                        ? Icons.person_search_outlined
                        : Icons.groups_outlined,
                    title: cherche ? 'Aucun prénom' : 'Le campus est vide',
                    body: cherche
                        ? 'Personne ne commence par « ${state.query} ».'
                        : "Personne d'autre n'est inscrit pour l'instant. "
                            'Invite tes amis à rejoindre Ding.',
                    action: cherche
                        ? TextButton(
                            onPressed: _clearSearch,
                            child: const Text('Voir tout le monde'),
                          )
                        : null,
                  );
                }

                return RefreshIndicator(
                  onRefresh: () async {
                    ref.invalidate(crushesProvider);
                    await ref.read(campusProvider.notifier).refresh();
                  },
                  child: ListView.builder(
                    controller: _scroll,
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
                    itemCount: state.items.length + 2,
                    itemBuilder: (_, i) {
                      if (i == 0) return _CountHeader(state: state);
                      final index = i - 1;
                      if (index == state.items.length) {
                        return _LoadMore(visible: state.hasMore);
                      }
                      final p = state.items[index];
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: _ProfileCard(
                          profile: p,
                          chosen: chosen.contains(p.id),
                          busy: _busy.contains(p.id),
                          onChanged: (active) =>
                              _setChoice(p, active: active),
                          onMore: () => _openActions(p),
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

/// « 24 personnes » / « 3 résultats » : on sait toujours combien il y en a.
class _CountHeader extends StatelessWidget {
  const _CountHeader({required this.state});

  final CampusState state;

  @override
  Widget build(BuildContext context) {
    final n = state.total;
    final cherche = state.query.isNotEmpty;
    final label = cherche
        ? '$n résultat${n > 1 ? 's' : ''}'
        : '$n personne${n > 1 ? 's' : ''}';

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Text(
        label,
        style: Theme.of(context)
            .textTheme
            .bodySmall
            ?.copyWith(letterSpacing: 0.4),
      ),
    );
  }
}

class _LoadMore extends StatelessWidget {
  const _LoadMore({required this.visible});

  final bool visible;

  @override
  Widget build(BuildContext context) {
    if (!visible) return const SizedBox(height: 8);
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 20),
      child: Center(
        child: SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      ),
    );
  }
}

class _ProfileCard extends StatelessWidget {
  const _ProfileCard({
    required this.profile,
    required this.chosen,
    required this.busy,
    required this.onChanged,
    required this.onMore,
  });

  final Profile profile;
  final bool chosen;
  final bool busy;
  final ValueChanged<bool> onChanged;
  final VoidCallback onMore;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 4, 10),
        child: Row(
          children: [
            InitialsAvatar(name: profile.firstName, radius: 21),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    profile.firstName,
                    style: theme.titleMedium,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (profile.detail.isNotEmpty)
                    Text(
                      profile.detail,
                      style: theme.bodySmall,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            _ChoiceButton(
              chosen: chosen,
              busy: busy,
              name: profile.firstName,
              onChanged: onChanged,
            ),
            IconButton(
              tooltip: 'Plus d’options',
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.more_vert, size: 20),
              color: DingColors.slate,
              onPressed: busy ? null : onMore,
            ),
          ],
        ),
      ),
    );
  }
}

class _ChoiceButton extends StatelessWidget {
  const _ChoiceButton({
    required this.chosen,
    required this.busy,
    required this.name,
    required this.onChanged,
  });

  final bool chosen;
  final bool busy;
  final String name;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    const size = Size(92, 38);

    if (busy) {
      return const SizedBox(
        width: 92,
        height: 38,
        child: Center(
          child: SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }

    return Semantics(
      button: true,
      selected: chosen,
      label: chosen ? '$name : choisi, appuyer pour retirer' : 'Choisir $name',
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 180),
        child: chosen
            ? FilledButton(
                key: const ValueKey('choisi'),
                style: FilledButton.styleFrom(minimumSize: size),
                onPressed: () => onChanged(false),
                child: const Text('Choisi'),
              )
            : OutlinedButton(
                key: const ValueKey('choisir'),
                style: OutlinedButton.styleFrom(minimumSize: size),
                onPressed: () => onChanged(true),
                child: const Text('Choisir'),
              ),
      ),
    );
  }
}
