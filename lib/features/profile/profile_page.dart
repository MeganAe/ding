import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers.dart';
import '../../core/theme.dart';
import '../../data/api_client.dart';
import '../../data/models.dart';

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
      // Le prénom apparaît aussi dans l'annuaire : on rafraîchit tout.
      ref.invalidate(myProfileProvider);
      ref.invalidate(profilesProvider);
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

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Profil', style: theme.headlineMedium),
            const SizedBox(height: 4),
            Text(
              "Ta position n'est jamais visible par les autres. Elle sert seulement à vérifier si un choix réciproque est à proximité.",
              style: theme.bodySmall,
            ),
            const SizedBox(height: 24),
            TextField(
              controller: _name,
              textCapitalization: TextCapitalization.words,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(hintText: 'Prénom'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _faculty,
              textCapitalization: TextCapitalization.words,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(hintText: 'Faculté'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _promotion,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _save(),
              decoration: const InputDecoration(hintText: 'Promotion'),
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _busy ? null : _save,
              child: _busy
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Text('Enregistrer'),
            ),

            const SizedBox(height: 32),
            Text('Visibilité', style: theme.titleMedium),
            const SizedBox(height: 4),
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
                    : 'Personne ne peut te voir ni te choisir. Tu peux toujours '
                        'choisir les autres.',
                style: theme.bodySmall,
              ),
            ),
            if (_discoverable == false)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  'Pense à enregistrer pour appliquer.',
                  style: theme.bodySmall,
                ),
              ),

            const SizedBox(height: 32),
            Text('Outils', style: theme.titleMedium),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: () => context.push(
                '/ring',
                extra: AlarmItem(
                  id: 'test',
                  createdAt: DateTime.now(),
                  otherId: 'test',
                  otherName: 'Quelqu’un',
                ),
              ),
              child: const Text("Tester l'alarme"),
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: _busy ? null : _confirmLogout,
              child: const Text('Me déconnecter'),
            ),
            const SizedBox(height: 32),
            TextButton(
              style: TextButton.styleFrom(
                foregroundColor: DingColors.signal,
                minimumSize: const Size.fromHeight(44),
              ),
              onPressed: _busy ? null : _confirmDelete,
              child: const Text('Supprimer mon compte'),
            ),
          ],
        ),
      ),
    );
  }
}
