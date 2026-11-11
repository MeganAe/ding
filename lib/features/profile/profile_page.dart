import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers.dart';
import '../../core/theme.dart';
import '../../core/widgets/initials_avatar.dart';
import '../../data/api_client.dart';
import '../../data/models.dart';

/// Le profil et les réglages, dans une seule page organisée en sections.
class ProfilePage extends ConsumerStatefulWidget {
  const ProfilePage({super.key});

  @override
  ConsumerState<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends ConsumerState<ProfilePage> {
  final _name = TextEditingController();
  final _faculty = TextEditingController();
  final _promotion = TextEditingController();
  bool _loaded = false;
  bool _busy = false;
  bool _discoverable = true;

  @override
  void initState() {
    super.initState();

    // Le profil ne doit être recopié dans les champs qu'une seule fois :
    // le faire dans build() écrasait ce que l'utilisateur était en train de
    // taper à chaque rechargement du provider.
    final cached = ref.read(myProfileProvider).valueOrNull;
    if (cached != null) _fill(cached);
    ref.listenManual(myProfileProvider, (_, next) {
      final p = next.valueOrNull;
      if (p != null) _fill(p);
    });
  }

  void _fill(Profile p) {
    if (_loaded) return;
    _loaded = true;
    _name.text = p.firstName;
    _faculty.text = p.faculty ?? '';
    _promotion.text = p.promotion ?? '';
    _discoverable = p.discoverable;
  }

  @override
  void dispose() {
    _name.dispose();
    _faculty.dispose();
    _promotion.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final messenger = ScaffoldMessenger.of(context);
    final firstName = _name.text.trim();
    if (firstName.isEmpty) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Ton prénom est obligatoire.')),
      );
      return;
    }
    setState(() => _busy = true);
    try {
      await ref.read(repositoryProvider).updateProfile(
            firstName: firstName,
            faculty: _faculty.text.trim(),
            promotion: _promotion.text.trim(),
            discoverable: _discoverable,
          );
      ref.invalidate(myProfileProvider);
      ref.invalidate(campusProvider);
      messenger.showSnackBar(
        const SnackBar(content: Text('Profil enregistré.')),
      );
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Enregistrement impossible. Réessaie.')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _unblock(Profile p) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(repositoryProvider).unblock(p.id);
      ref.invalidate(blockedProvider);
      ref.invalidate(campusProvider);
      messenger.showSnackBar(
        SnackBar(content: Text('${p.firstName} est débloqué.')),
      );
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _confirmLogout() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Te déconnecter ?'),
        content: const Text(
          'Tu devras te reconnecter pour voir tes alarmes. '
          'Tes choix sont conservés.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Annuler'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Me déconnecter'),
          ),
        ],
      ),
    );
    if (ok == true) await ref.read(repositoryProvider).logOut();
  }

  /// Suppression définitive. Le mot de passe est redemandé : un téléphone
  /// déverrouillé ne doit pas suffire à effacer un compte.
  Future<void> _confirmDelete() async {
    final messenger = ScaffoldMessenger.of(context);
    final password = TextEditingController();

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Supprimer mon compte ?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Cette action est définitive : tes choix, tes alarmes et ta '
              'position sont effacés. Rien ne peut être récupéré.',
            ),
            const SizedBox(height: 16),
            TextField(
              controller: password,
              obscureText: true,
              autofocus: true,
              decoration: const InputDecoration(hintText: 'Ton mot de passe'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Annuler'),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: DingColors.signal),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );

    // Le contrôleur n'est pas libéré : le champ peut encore être monté
    // pendant l'animation de fermeture du dialogue.
    final pwd = password.text;
    if (ok != true || !mounted) return;

    setState(() => _busy = true);
    try {
      await ref.read(repositoryProvider).deleteAccount(pwd);
      // Le jeton est effacé : le routeur ramène à l'écran de connexion.
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Suppression impossible. Réessaie.')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    final me = ref.watch(myProfileProvider).valueOrNull;
    final blocked = ref.watch(blockedProvider).valueOrNull ?? const <Profile>[];

    return SafeArea(
      bottom: false,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Profil', style: theme.headlineMedium),
            const SizedBox(height: 16),

            // Carte d'identité : qui je suis, et avec quelle adresse.
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    InitialsAvatar(
                      name: _name.text.isEmpty ? (me?.firstName ?? '') : _name.text,
                      radius: 28,
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            me?.firstName.isNotEmpty == true
                                ? me!.firstName
                                : 'Toi',
                            style: theme.titleLarge,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          if (me?.email != null)
                            Text(
                              me!.email!,
                              style: theme.bodySmall,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),

            const _SectionLabel('Mon profil'),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _Field(label: 'Prénom', controller: _name),
                    const SizedBox(height: 14),
                    _Field(
                      label: 'Faculté',
                      controller: _faculty,
                      hint: 'Ex. Médecine',
                    ),
                    const SizedBox(height: 14),
                    _Field(
                      label: 'Promotion',
                      controller: _promotion,
                      hint: 'Ex. L2',
                      done: true,
                      onSubmitted: _save,
                    ),
                    const SizedBox(height: 18),
                    FilledButton(
                      onPressed: _busy ? null : _save,
                      child: _busy
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: DingColors.paper,
                              ),
                            )
                          : const Text('Enregistrer'),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),

            const _SectionLabel('Visibilité'),
            Card(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 6, 16, 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      value: _discoverable,
                      onChanged: (v) => setState(() => _discoverable = v),
                      title: Text(
                        'Apparaître dans l’annuaire',
                        style: theme.bodyMedium,
                      ),
                      subtitle: Text(
                        _discoverable
                            ? 'Les autres étudiants peuvent te voir et te choisir.'
                            : 'Personne ne peut te voir ni te choisir. Tu peux '
                                'toujours choisir les autres.',
                        style: theme.bodySmall,
                      ),
                    ),
                    if (!_discoverable)
                      Text(
                        'Pense à enregistrer pour appliquer.',
                        style: theme.bodySmall
                            ?.copyWith(color: DingColors.signal),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),

            const _SectionLabel('Personnes bloquées'),
            Card(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                child: blocked.isEmpty
                    ? Text(
                        'Personne n’est bloqué. Tu peux bloquer quelqu’un '
                        'depuis l’annuaire.',
                        style: theme.bodySmall,
                      )
                    : Column(
                        children: [
                          for (final p in blocked)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 6),
                              child: Row(
                                children: [
                                  InitialsAvatar(
                                    name: p.firstName,
                                    radius: 16,
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      p.firstName,
                                      style: theme.bodyMedium,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  TextButton(
                                    onPressed: () => _unblock(p),
                                    child: const Text('Débloquer'),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
              ),
            ),
            const SizedBox(height: 24),

            const _SectionLabel('Ta vie privée'),
            Card(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
                child: Text(
                  'Ta position n’est jamais visible par les autres : elle sert '
                  'seulement à vérifier qu’un choix réciproque est tout près. '
                  'Elle est effacée au bout de 24 heures.',
                  style: theme.bodySmall,
                ),
              ),
            ),
            const SizedBox(height: 24),

            const _SectionLabel('Le compte'),
            Card(
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.notifications_active_outlined),
                    title: const Text("Tester l'alarme"),
                    subtitle: const Text("Voir l'écran qui sonne, sans attendre."),
                    onTap: () => context.push(
                      '/ring',
                      extra: AlarmItem(
                        id: 'test',
                        createdAt: DateTime.now(),
                        otherId: 'test',
                        otherName: 'Quelqu’un',
                      ),
                    ),
                  ),
                  const Divider(),
                  ListTile(
                    leading: const Icon(Icons.logout),
                    title: const Text('Me déconnecter'),
                    onTap: _busy ? null : _confirmLogout,
                  ),
                  const Divider(),
                  ListTile(
                    leading: const Icon(
                      Icons.delete_outline,
                      color: DingColors.signal,
                    ),
                    title: const Text(
                      'Supprimer mon compte',
                      style: TextStyle(color: DingColors.signal),
                    ),
                    onTap: _busy ? null : _confirmDelete,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Text(
        text.toUpperCase(),
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              letterSpacing: 1.1,
              fontWeight: FontWeight.w600,
              fontSize: 11,
              color: DingColors.slate,
            ),
      ),
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({
    required this.label,
    required this.controller,
    this.hint,
    this.done = false,
    this.onSubmitted,
  });

  final String label;
  final TextEditingController controller;
  final String? hint;
  final bool done;
  final VoidCallback? onSubmitted;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: theme.bodySmall?.copyWith(
            color: DingColors.ink,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          textCapitalization: TextCapitalization.words,
          textInputAction: done ? TextInputAction.done : TextInputAction.next,
          onSubmitted: done && onSubmitted != null ? (_) => onSubmitted!() : null,
          decoration: InputDecoration(hintText: hint),
        ),
      ],
    );
  }
}
