import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers.dart';
import '../../core/theme.dart';
import '../../core/widgets/pill_button.dart';
import '../../data/api_client.dart';

/// Confirmation de l'adresse email.
///
/// Tant qu'elle n'est pas faite, l'app fonctionne (annuaire, choix secrets)
/// mais l'alarme ne sonne pas : c'est la seule façon simple d'empêcher
/// quelqu'un de créer un compte jetable avec l'adresse d'un autre pour faire
/// sonner un téléphone.
class VerifyEmailPage extends ConsumerStatefulWidget {
  const VerifyEmailPage({super.key});

  @override
  ConsumerState<VerifyEmailPage> createState() => _VerifyEmailPageState();
}

class _VerifyEmailPageState extends ConsumerState<VerifyEmailPage> {
  final _code = TextEditingController();
  bool _busy = false;
  String? _message;
  bool _envoye = false;

  /// Secondes avant de pouvoir redemander un code (l'API impose une minute).
  int _attente = 0;
  Timer? _compte;

  @override
  void dispose() {
    _compte?.cancel();
    _code.dispose();
    super.dispose();
  }

  void _demarrerAttente(int secondes) {
    _compte?.cancel();
    setState(() => _attente = secondes);
    _compte = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return t.cancel();
      setState(() => _attente--);
      if (_attente <= 0) t.cancel();
    });
  }

  Future<void> _valider() async {
    final code = _code.text.trim();
    if (code.length != 6) {
      setState(() => _message = 'Le code fait six chiffres.');
      return;
    }

    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await ref.read(repositoryProvider).verifyEmail(code);
      ref.invalidate(myProfileProvider);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Adresse confirmée. L’alarme peut sonner.')),
      );
      final router = GoRouter.maybeOf(context);
      if (router != null && router.canPop()) {
        router.pop();
      } else if (router != null) {
        router.go('/home');
      } else {
        // Test ou aperçu : pas de routeur, rien à faire.
        Navigator.maybePop(context);
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _message = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _renvoyer() async {
    if (_attente > 0 || _busy) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await ref.read(repositoryProvider).resendVerification();
      if (!mounted) return;
      setState(() => _envoye = true);
      _demarrerAttente(60);
    } on ApiException catch (e) {
      if (mounted) {
        setState(() => _message = e.message);
        // 429 : le serveur dit combien de temps attendre, on lance le compte.
        if (e.status == 429) _demarrerAttente(60);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    final me = ref.watch(myProfileProvider).valueOrNull;

    return Scaffold(
      backgroundColor: DingColors.paper,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: IconButton(
                tooltip: 'Retour',
                padding: EdgeInsets.zero,
                alignment: Alignment.centerLeft,
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
            ),
            const SizedBox(height: 12),
            Text(
              'DING · CONFIRMATION',
              style: theme.bodySmall?.copyWith(
                letterSpacing: 1.2,
                fontWeight: FontWeight.w600,
                color: DingColors.slate,
              ),
            ),
            const SizedBox(height: 8),
            Text('Ton adresse email', style: theme.headlineSmall),
            const SizedBox(height: 10),
            Text(
              me?.email == null
                  ? 'Nous t’avons envoyé un code à six chiffres.'
                  : 'Nous avons envoyé un code à six chiffres à '
                      '${me!.email}.',
              style: theme.bodyMedium,
            ),
            const SizedBox(height: 6),
            Text(
              'Tant que l’adresse n’est pas confirmée, l’alarme ne peut pas '
              'sonner. Le reste de l’app fonctionne normalement.',
              style: theme.bodySmall,
            ),
            const SizedBox(height: 24),
            TextField(
              controller: _code,
              keyboardType: TextInputType.number,
              textAlign: TextAlign.center,
              maxLength: 6,
              autofocus: true,
              style: theme.headlineSmall?.copyWith(letterSpacing: 10),
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              onSubmitted: (_) => _busy ? null : _valider(),
              decoration: const InputDecoration(
                hintText: '000000',
                counterText: '',
              ),
            ),
            if (_message != null) ...[
              const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(top: 2),
                    child: Icon(
                      Icons.error_outline,
                      size: 18,
                      color: DingColors.signal,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _message!,
                      style: theme.bodyMedium
                          ?.copyWith(color: DingColors.signal),
                    ),
                  ),
                ],
              ),
            ],
            if (_envoye) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  const Icon(
                    Icons.mark_email_read_outlined,
                    size: 18,
                    color: DingColors.ink,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Nouveau code envoyé.',
                      style: theme.bodySmall?.copyWith(color: DingColors.ink),
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 20),
            FilledButton(
              onPressed: _busy ? null : _valider,
              child: _busy
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: DingColors.paper,
                      ),
                    )
                  : const Text('Confirmer'),
            ),
            const SizedBox(height: 8),
            Center(
              child: PillButton(
                label: _attente > 0
                    ? 'Renvoyer dans ${_attente}s'
                    : 'Renvoyer un code',
                onPressed: (_busy || _attente > 0) ? null : _renvoyer,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'Rien reçu ? Regarde dans les indésirables, et vérifie que '
              'l’adresse ne contient pas de faute. Si l’adresse est fausse, '
              'il faut supprimer le compte et le recréer depuis le profil.',
              style: theme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}
