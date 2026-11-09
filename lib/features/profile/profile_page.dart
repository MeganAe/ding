import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers.dart';
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

  @override
  void dispose() {
    _name.dispose();
    _faculty.dispose();
    _promotion.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final messenger = ScaffoldMessenger.of(context);
    if (_name.text.trim().isEmpty) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Ton prénom est obligatoire.')),
      );
      return;
    }
    setState(() => _busy = true);
    try {
      await ref.read(repositoryProvider).updateProfile(
            firstName: _name.text.trim(),
            faculty: _faculty.text.trim(),
            promotion: _promotion.text.trim(),
          );
      ref.invalidate(myProfileProvider);
      messenger.showSnackBar(
        const SnackBar(content: Text('Profil enregistré.')),
      );
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Enregistrement impossible. Réessaie.')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;

    ref.watch(myProfileProvider).whenData((p) {
      if (!_loaded && p != null) {
        _name.text = p.firstName;
        _faculty.text = p.faculty ?? '';
        _promotion.text = p.promotion ?? '';
        _loaded = true;
      }
    });

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
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
              decoration: const InputDecoration(hintText: 'Prénom'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _faculty,
              decoration: const InputDecoration(hintText: 'Faculté'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _promotion,
              decoration: const InputDecoration(hintText: 'Promotion'),
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _busy ? null : _save,
              child: const Text('Enregistrer'),
            ),
            const SizedBox(height: 12),
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
              onPressed: () => ref.read(repositoryProvider).logOut(),
              child: const Text('Me déconnecter'),
            ),
          ],
        ),
      ),
    );
  }
}
