import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/config.dart';
import '../../core/providers.dart';
import '../../core/theme.dart';

class AuthPage extends ConsumerStatefulWidget {
  const AuthPage({super.key});

  @override
  ConsumerState<AuthPage> createState() => _AuthPageState();
}

class _AuthPageState extends ConsumerState<AuthPage> {
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _signup = false;
  bool _busy = false;
  String? _message;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final name = _name.text.trim();
    final email = _email.text.trim();
    final password = _password.text;

    if (email.isEmpty || password.length < 6 || (_signup && name.isEmpty)) {
      setState(() => _message = _signup
          ? 'Renseigne ton prénom, ton email et un mot de passe de 6 caractères minimum.'
          : 'Renseigne ton email et ton mot de passe.');
      return;
    }
    if (_signup &&
        Config.allowedEmailDomain.isNotEmpty &&
        !email.toLowerCase().endsWith('@${Config.allowedEmailDomain}')) {
      setState(() =>
          _message = 'Utilise ton adresse @${Config.allowedEmailDomain}.');
      return;
    }

    setState(() {
      _busy = true;
      _message = null;
    });
    final auth = ref.read(supabaseProvider).auth;
    try {
      if (_signup) {
        final res = await auth.signUp(
          email: email,
          password: password,
          data: {'first_name': name},
        );
        if (res.session == null && mounted) {
          setState(() {
            _signup = false;
            _message = 'Compte créé. Confirme ton email, puis connecte-toi.';
          });
        }
      } else {
        await auth.signInWithPassword(email: email, password: password);
      }
    } on AuthException catch (e) {
      if (mounted) {
        setState(() => _message =
            _signup ? e.message : 'Email ou mot de passe incorrect.');
      }
    } catch (_) {
      if (mounted) {
        setState(() => _message =
            'Connexion impossible. Vérifie ta connexion internet.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 48, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Ding', style: theme.displayLarge),
              const SizedBox(height: 8),
              Text(
                _signup ? 'Crée ton compte.' : 'Connecte-toi.',
                style: theme.titleLarge,
              ),
              const SizedBox(height: 32),
              if (_signup) ...[
                TextField(
                  controller: _name,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(hintText: 'Prénom'),
                ),
                const SizedBox(height: 12),
              ],
              TextField(
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                autofillHints: const [AutofillHints.email],
                decoration: const InputDecoration(hintText: 'Email'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _password,
                obscureText: true,
                decoration: const InputDecoration(hintText: 'Mot de passe'),
              ),
              if (_message != null) ...[
                const SizedBox(height: 16),
                Text(
                  _message!,
                  style: theme.bodyMedium?.copyWith(color: DingColors.signal),
                ),
              ],
              const SizedBox(height: 24),
              FilledButton(
                onPressed: _busy ? null : _submit,
                child: Text(_signup ? 'Créer mon compte' : 'Me connecter'),
              ),
              const SizedBox(height: 8),
              Center(
                child: TextButton(
                  onPressed: _busy
                      ? null
                      : () => setState(() {
                            _signup = !_signup;
                            _message = null;
                          }),
                  child: Text(_signup
                      ? "J'ai déjà un compte"
                      : "Pas encore de compte ? Inscris-toi"),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
