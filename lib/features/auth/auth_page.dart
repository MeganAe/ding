import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/config.dart';
import '../../core/providers.dart';
import '../../core/theme.dart';
import '../../data/api_client.dart';

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
  bool _showPassword = false;
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
    try {
      final repo = ref.read(repositoryProvider);
      if (_signup) {
        await repo.signUp(firstName: name, email: email, password: password);
      } else {
        await repo.logIn(email: email, password: password);
      }
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
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: SizedBox(
                  height: 200,
                  width: double.infinity,
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 250),
                    child: Image.asset(
                      _signup
                          ? 'assets/images/auth_signup.jpg'
                          : 'assets/images/auth_login.jpg',
                      key: ValueKey(_signup),
                      fit: BoxFit.cover,
                      alignment: _signup
                          ? const Alignment(0, -0.3)
                          : const Alignment(0, 0.6),
                      filterQuality: FilterQuality.high,
                      width: double.infinity,
                      height: 200,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Image.asset('assets/images/logo.png', height: 56),
              const SizedBox(height: 16),
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
                autocorrect: false,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(hintText: 'Email'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _password,
                obscureText: !_showPassword,
                autofillHints: [
                  _signup ? AutofillHints.newPassword : AutofillHints.password,
                ],
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _busy ? null : _submit(),
                decoration: InputDecoration(
                  hintText: 'Mot de passe',
                  suffixIcon: IconButton(
                    tooltip: _showPassword
                        ? 'Masquer le mot de passe'
                        : 'Afficher le mot de passe',
                    icon: Icon(
                      _showPassword
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined,
                    ),
                    onPressed: () =>
                        setState(() => _showPassword = !_showPassword),
                  ),
                ),
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
              if (!_signup)
                Center(
                  child: TextButton(
                    onPressed: _busy ? null : () => context.push('/forgot'),
                    child: const Text('Mot de passe oublié ?'),
                  ),
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
