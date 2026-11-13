import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/config.dart';
import '../../core/providers.dart';
import '../../core/theme.dart';
import '../../core/widgets/hero_media.dart';
import '../../core/widgets/pill_button.dart';
import '../../data/api_client.dart';

/// Connexion et inscription : le même écran, deux modes.
///
/// La mise en page reprend celle de l'onboarding — une photo pleine largeur
/// qui se dissout dans le papier par un flou progressif, puis du texte et des
/// champs posés sur ce papier. Seule différence : ici le contenu défile, parce
/// que le clavier occupe la moitié de l'écran.
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

  /// Case des conditions d'utilisation : obligatoire à l'inscription, et
  /// remise à zéro dès qu'on repasse en mode connexion.
  bool _accepted = false;
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
    if (_signup && !_accepted) {
      setState(() => _message =
          'Coche la case pour accepter les conditions d’utilisation.');
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
        await repo.signUp(
          firstName: name,
          email: email,
          password: password,
          acceptTerms: _accepted,
        );
      } else {
        await repo.logIn(email: email, password: password);
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _message = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _switchMode() {
    if (_busy) return;
    setState(() {
      _signup = !_signup;
      _message = null;
      _accepted = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    final size = MediaQuery.sizeOf(context);
    final safeBottom = MediaQuery.paddingOf(context).bottom;

    // Clavier ouvert, la photo s'efface : le formulaire garde la priorité.
    final keyboardOpen = MediaQuery.viewInsetsOf(context).bottom > 0;
    // 30 % plutôt que 40 % : les liens légaux ajoutés sous le bouton
    // repoussaient le bouton de bascule (« J'ai déjà un compte ») sous la
    // ligne de flottaison sur un téléphone de 844 px. La photo reste large,
    // mais on ne descend plus pour trouver le reste du formulaire.
    final heroHeight = (size.height * 0.30).clamp(180.0, 300.0);

    return Scaffold(
      backgroundColor: DingColors.paper,
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AnimatedSize(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              alignment: Alignment.topCenter,
              child: keyboardOpen
                  ? const SizedBox(width: double.infinity, height: 0)
                  : SizedBox(
                      height: heroHeight,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          // La photo change de page quand on passe de
                          // « se connecter » à « s'inscrire ».
                          AnimatedSwitcher(
                            duration: const Duration(milliseconds: 280),
                            child: HeroMedia(
                              key: ValueKey(_signup),
                              asset: _signup
                                  ? 'assets/images/auth_signup.jpg'
                                  : 'assets/images/auth_login.jpg',
                              // Inscription : deux visages en haut de l'image,
                              // donc on garde le centre. Connexion : le couple
                              // est en bas, on cale l'image sur son bas pour
                              // qu'il tombe juste avant le fondu au papier.
                              alignment: _signup
                                  ? Alignment.center
                                  : Alignment.bottomCenter,
                            ),
                          ),

                          // La marque, posée sur la fin du fondu — là où la
                          // photo est déjà redevenue du papier.
                          Positioned(
                            left: 24,
                            bottom: 0,
                            child: Row(
                              children: [
                                Image.asset(
                                  'assets/images/logo.png',
                                  height: 34,
                                ),
                                const SizedBox(width: 8),
                                Text('Ding', style: theme.headlineMedium),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(24, 20, 24, 24 + safeBottom),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    _signup ? 'Crée ton compte.' : 'Connecte-toi.',
                    style: theme.headlineMedium,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _signup ? _signupSubtitle() : _loginSubtitle(),
                    style: theme.bodyLarge,
                  ),
                  const SizedBox(height: 24),
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
                      _signup
                          ? AutofillHints.newPassword
                          : AutofillHints.password,
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
                  if (_signup) ...[
                    const SizedBox(height: 8),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: 36,
                          height: 36,
                          child: Checkbox(
                            value: _accepted,
                            visualDensity: VisualDensity.compact,
                            materialTapTargetSize:
                                MaterialTapTargetSize.shrinkWrap,
                            onChanged: _busy
                                ? null
                                : (v) =>
                                    setState(() => _accepted = v ?? false),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Text(
                              'J’accepte les conditions d’utilisation et la '
                              'politique de confidentialité.',
                              style: theme.bodySmall,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                  if (_message != null) ...[
                    const SizedBox(height: 16),
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
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: _busy ? null : _submit,
                    child: _busy
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: DingColors.paper,
                            ),
                          )
                        : Text(_signup ? 'Créer mon compte' : 'Me connecter'),
                  ),
                  const SizedBox(height: 4),
                  // `Wrap` plutôt que `Row` : sur un écran étroit, les deux
                  // liens passent à la ligne au lieu de déborder.
                  Wrap(
                    alignment: WrapAlignment.center,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      _LegalLink(
                        label: 'Conditions',
                        onTap: _busy ? null : () => context.push('/legal/terms'),
                      ),
                      Text('·', style: theme.bodySmall),
                      _LegalLink(
                        label: 'Confidentialité',
                        onTap:
                            _busy ? null : () => context.push('/legal/privacy'),
                      ),
                    ],
                  ),
                  if (!_signup)
                    Center(
                      child: TextButton(
                        onPressed: _busy ? null : () => context.push('/forgot'),
                        child: Text(
                          'Mot de passe oublié ?',
                          style: theme.bodyMedium
                              ?.copyWith(color: DingColors.slate),
                        ),
                      ),
                    )
                  else
                    const SizedBox(height: 16),
                  Center(
                    child: PillButton(
                      label: _signup
                          ? "J'ai déjà un compte"
                          : 'Pas encore de compte ? Inscris-toi',
                      onPressed: _busy ? null : _switchMode,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _loginSubtitle() {
    return 'Ton compte te rend à tes choix secrets, et à ceux qui t\'ont '
        'choisi.';
  }

  String _signupSubtitle() {
    final domain = Config.allowedEmailDomain;
    if (domain.isEmpty) {
      return 'Un prénom, un mot de passe, et c\'est parti. Rien n\'est public.';
    }
    return 'Un prénom, un mot de passe, ton adresse @$domain. Rien n\'est '
        'public.';
  }
}

/// Lien discret vers un texte légal, au même niveau que le reste du pied de
/// page : lisible, sans concurrencer le bouton principal.
class _LegalLink extends StatelessWidget {
  const _LegalLink({required this.label, required this.onTap});

  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: onTap,
      style: TextButton.styleFrom(
        foregroundColor: DingColors.slate,
        padding: const EdgeInsets.symmetric(horizontal: 6),
        minimumSize: const Size(0, 32),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      child: Text(label, style: Theme.of(context).textTheme.bodySmall),
    );
  }
}
