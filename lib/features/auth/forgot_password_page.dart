import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers.dart';
import '../../core/theme.dart';
import '../../data/api_client.dart';

/// Mot de passe oublié, en deux temps sur un seul écran.
///
/// L'email contient un code à 6 chiffres plutôt qu'un lien : l'app n'a pas de
/// liens profonds, et un code se recopie à la main sans dépendre d'un domaine
/// vérifié.
class ForgotPasswordPage extends ConsumerStatefulWidget {
  const ForgotPasswordPage({super.key});

  @override
  ConsumerState<ForgotPasswordPage> createState() => _ForgotPasswordPageState();
}

class _ForgotPasswordPageState extends ConsumerState<ForgotPasswordPage> {
  final _email = TextEditingController();
  final _code = TextEditingController();
  final _password = TextEditingController();
  bool _sent = false;
  bool _busy = false;
  String? _message;
  String? _info;

  @override
  void dispose() {
    _email.dispose();
    _code.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _request() async {
    final email = _email.text.trim();
    if (email.isEmpty) {
      setState(() => _message = 'Renseigne ton adresse email.');
      return;
    }
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await ref.read(repositoryProvider).requestPasswordReset(email);
      if (!mounted) return;
      setState(() {
        _sent = true;
        _info = 'Si un compte existe pour $email, un code à 6 chiffres vient '
            "d'être envoyé. Il expire dans 15 minutes.";
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _message = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _submit() async {
    final email = _email.text.trim();
    final code = _code.text.trim();
    final password = _password.text;

    if (code.length != 6 || password.length < 6) {
      setState(() => _message =
          'Saisis le code à 6 chiffres et un mot de passe de 6 caractères minimum.');
      return;
    }
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      // En cas de succès le jeton est enregistré : le routeur bascule
      // automatiquement sur l'accueil.
      await ref.read(repositoryProvider).resetPassword(
            email: email,
            code: code,
            password: password,
          );
    } on ApiException catch (e) {
      if (mounted) setState(() => _message = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/auth'),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Mot de passe oublié', style: theme.headlineMedium),
              const SizedBox(height: 8),
              Text(
                'On t’envoie un code à 6 chiffres par email. Tu choisiras un '
                'nouveau mot de passe juste après.',
                style: theme.bodyMedium,
              ),
              const SizedBox(height: 24),
              TextField(
                controller: _email,
                enabled: !_sent,
                keyboardType: TextInputType.emailAddress,
                autofillHints: const [AutofillHints.email],
                autocorrect: false,
                decoration: const InputDecoration(hintText: 'Email'),
              ),
              if (_info != null) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: DingColors.mist,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(_info!, style: theme.bodySmall),
                ),
              ],
              if (_sent) ...[
                const SizedBox(height: 16),
                TextField(
                  controller: _code,
                  keyboardType: TextInputType.number,
                  maxLength: 6,
                  autofillHints: const [AutofillHints.oneTimeCode],
                  decoration: const InputDecoration(
                    hintText: 'Code à 6 chiffres',
                    counterText: '',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _password,
                  obscureText: true,
                  autofillHints: const [AutofillHints.newPassword],
                  decoration: const InputDecoration(
                    hintText: 'Nouveau mot de passe',
                  ),
                ),
              ],
              if (_message != null) ...[
                const SizedBox(height: 16),
                Text(
                  _message!,
                  style: theme.bodyMedium?.copyWith(color: DingColors.signal),
                ),
              ],
              const SizedBox(height: 24),
              FilledButton(
                onPressed: _busy ? null : (_sent ? _submit : _request),
                child: _busy
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Text(_sent ? 'Changer mon mot de passe' : 'Recevoir un code'),
              ),
              if (_sent) ...[
                const SizedBox(height: 8),
                Center(
                  child: TextButton(
                    onPressed: _busy
                        ? null
                        : () => setState(() {
                              _sent = false;
                              _info = null;
                              _message = null;
                            }),
                    child: const Text('Utiliser une autre adresse'),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
