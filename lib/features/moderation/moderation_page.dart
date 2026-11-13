import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers.dart';
import '../../core/theme.dart';
import '../../core/widgets/empty_state.dart';
import '../../core/widgets/initials_avatar.dart';
import '../../data/api_client.dart';
import '../../data/models.dart';
import '../../data/repository.dart';

/// File de modération : les personnes signalées, et les deux décisions
/// possibles. Réservée aux comptes dont l'email figure dans ADMIN_EMAILS —
/// le serveur le vérifie à chaque appel, cet écran ne fait que l'afficher.
class ModerationPage extends ConsumerStatefulWidget {
  const ModerationPage({super.key});

  @override
  ConsumerState<ModerationPage> createState() => _ModerationPageState();
}

class _ModerationPageState extends ConsumerState<ModerationPage> {
  /// Profil en cours de traitement : évite deux décisions simultanées.
  String? _busy;

  /// false = seulement les signalements à traiter ; true = tout l'historique,
  /// comptes suspendus compris (pour pouvoir les réactiver).
  bool _tous = false;

  Future<void> _decide(ModerationItem item) async {
    if (_busy != null) return;

    final decision = await showModalBottomSheet<_Decision>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _DecisionSheet(item: item),
    );
    if (decision == null || !mounted) return;

    if (decision.action == _Deci.ban) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          title: Text('Suspendre ${item.firstName} ?'),
          content: const Text(
            'La connexion sera coupée, le profil disparaîtra de l’annuaire, '
            'et ses choix comme sa position seront effacés. Une réactivation '
            'demande une intervention manuelle sur la base.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Annuler'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: DingColors.signal),
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Suspendre'),
            ),
          ],
        ),
      );
      if (ok != true) return;
    }

    setState(() => _busy = item.id);
    try {
      final repo = ref.read(repositoryProvider);
      if (decision.action == _Deci.restore) {
        await repo.restoreAccount(item.id);
      } else {
        await repo.resolveReport(
          item.id,
          action: decision.action == _Deci.ban
              ? ReportAction.ban
              : ReportAction.dismiss,
          note: decision.note,
        );
      }
      ref.invalidate(moderationQueueProvider);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(switch (decision.action) {
            _Deci.ban => '${item.firstName} est suspendu.',
            _Deci.restore => '${item.firstName} peut de nouveau se connecter.',
            _Deci.dismiss => 'Signalement classé sans suite.',
          }),
        ),
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    final queue = ref.watch(moderationQueueProvider(_tous));

    return Scaffold(
      backgroundColor: DingColors.paper,
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 24, 0),
              child: Row(
                children: [
                  IconButton(
                    tooltip: 'Retour',
                    icon: const Icon(Icons.arrow_back, color: DingColors.ink),
                    onPressed: () {
                      final router = GoRouter.maybeOf(context);
                      if (router != null && router.canPop()) {
                        router.pop();
                      } else if (router != null) {
                        router.go('/home');
                      } else {
                        Navigator.maybePop(context);
                      }
                    },
                  ),
                  Expanded(
                    child: Text(
                      'Signalements',
                      style: theme.headlineSmall,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    tooltip: _tous
                        ? 'Voir seulement ce qui reste à traiter'
                        : 'Voir aussi les comptes suspendus',
                    icon: Icon(
                      _tous ? Icons.visibility : Icons.visibility_outlined,
                      color: _tous ? DingColors.ink : DingColors.slate,
                    ),
                    onPressed: () => setState(() => _tous = !_tous),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 4, 24, 0),
              child: Text(
                'Une ligne par personne signalée, avec le nombre de '
                'signalements reçus. Les signalants ne sont pas identifiés.',
                style: theme.bodySmall,
              ),
            ),
            Expanded(
              child: queue.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, __) => EmptyState(
                  icon: Icons.cloud_off_outlined,
                  title: 'File inaccessible',
                  body: e is ApiException
                      ? e.message
                      : 'Impossible de charger les signalements.',
                  action: OutlinedButton(
                    onPressed: () =>
                        ref.invalidate(moderationQueueProvider(_tous)),
                    child: const Text('Réessayer'),
                  ),
                ),
                data: (items) {
                  Future<void> reload() async {
                    ref.invalidate(moderationQueueProvider(_tous));
                    await ref.read(moderationQueueProvider(_tous).future);
                  }

                  if (items.isEmpty) {
                    return RefreshIndicator(
                      onRefresh: reload,
                      child: ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        children: const [
                          EmptyState(
                            icon: Icons.inbox_outlined,
                            title: 'Rien à traiter',
                            body: 'Aucun signalement en attente. La file se '
                                'remplit seulement quand quelqu’un signale un '
                                'profil depuis l’annuaire.',
                          ),
                        ],
                      ),
                    );
                  }

                  return RefreshIndicator(
                    onRefresh: reload,
                    child: ListView.separated(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
                      itemCount: items.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (_, i) => _ReportCard(
                        item: items[i],
                        busy: _busy == items[i].id,
                        onTap: _busy == null ? () => _decide(items[i]) : null,
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReportCard extends StatelessWidget {
  const _ReportCard({
    required this.item,
    required this.busy,
    required this.onTap,
  });

  final ModerationItem item;
  final bool busy;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    final details = item.lastDetails;

    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 14, 14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              InitialsAvatar(name: item.firstName, radius: 22),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            item.firstName.isEmpty
                                ? 'Profil sans prénom'
                                : item.firstName,
                            style: theme.titleSmall,
                          ),
                        ),
                        if (busy)
                          const SizedBox(
                            height: 16,
                            width: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                      ],
                    ),
                    if (item.faculty != null)
                      Text(item.faculty!, style: theme.bodySmall),
                    if (item.banned)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          'Compte suspendu',
                          style: theme.bodySmall?.copyWith(
                            color: DingColors.signal,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    const SizedBox(height: 6),
                    Text(
                      '${item.openReports} signalement'
                      '${item.openReports > 1 ? 's' : ''} · ${item.reasonLabel}',
                      style: theme.bodySmall?.copyWith(color: DingColors.ink),
                    ),
                    if (details != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          '« $details »',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.bodySmall,
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 4),
              const Icon(
                Icons.chevron_right,
                size: 20,
                color: DingColors.slate,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Les trois issues possibles d'une ligne.
enum _Deci { dismiss, ban, restore }

/// Ce que le modérateur a choisi, note interne comprise.
class _Decision {
  const _Decision(this.action, this.note);
  final _Deci action;
  final String? note;
}

/// Feuille de décision : deux issues, une note facultative.
class _DecisionSheet extends StatefulWidget {
  const _DecisionSheet({required this.item});

  final ModerationItem item;

  @override
  State<_DecisionSheet> createState() => _DecisionSheetState();
}

class _DecisionSheetState extends State<_DecisionSheet> {
  final _note = TextEditingController();

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  void _close(_Deci action) {
    final note = _note.text.trim();
    Navigator.of(context).pop(_Decision(action, note.isEmpty ? null : note));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    final item = widget.item;

    return Padding(
      // Le clavier ne doit pas recouvrir les boutons.
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        top: 20,
        bottom: 24 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: DingColors.mist,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 18),
            Text(
              item.firstName.isEmpty ? 'Profil sans prénom' : item.firstName,
              style: theme.headlineSmall,
            ),
            const SizedBox(height: 4),
            Text(
              '${item.reports} signalement${item.reports > 1 ? 's' : ''} reçu'
              '${item.reports > 1 ? 's' : ''} · ${item.reasonLabel}',
              style: theme.bodySmall,
            ),
            if (item.lastDetails != null) ...[
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: DingColors.paper,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '« ${item.lastDetails} »',
                  style: theme.bodyMedium?.copyWith(height: 1.4),
                ),
              ),
            ],
            const SizedBox(height: 16),
            TextField(
              controller: _note,
              maxLength: 300,
              maxLines: 2,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                hintText: 'Note interne (facultatif) — pourquoi cette décision',
                counterText: '',
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'La note reste côté équipe : personne d’autre ne la voit.',
              style: theme.bodySmall,
            ),
            const SizedBox(height: 20),
            if (item.banned) ...[
              Text(
                'Ce compte est suspendu. Le réactiver lui rend la connexion et '
                'le remet dans l’annuaire.',
                style: theme.bodySmall,
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => _close(_Deci.restore),
                  child: const Text('Réactiver le compte'),
                ),
              ),
            ] else ...[
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: () => _close(_Deci.dismiss),
                  child: const Text('Classer sans suite'),
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: DingColors.signal,
                  ),
                  onPressed: () => _close(_Deci.ban),
                  child: const Text('Suspendre le compte'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
