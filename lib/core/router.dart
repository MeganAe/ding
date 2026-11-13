import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../data/models.dart';
import '../features/alarm/ring_page.dart';
import '../features/auth/auth_page.dart';
import '../features/auth/forgot_password_page.dart';
import '../features/auth/verify_email_page.dart';
import '../features/home/home_shell.dart';
import '../features/legal/legal_page.dart';
import '../features/legal/legal_texts.dart';
import '../features/moderation/moderation_page.dart';
import '../features/onboarding/onboarding_page.dart';
import 'providers.dart';
import 'theme.dart';

final routerProvider = Provider<GoRouter>((ref) {
  final refresh = ValueNotifier<int>(0);
  ref.listen(sessionProvider, (_, __) => refresh.value++);
  ref.listen(onboardingDoneProvider, (_, __) => refresh.value++);
  ref.onDispose(refresh.dispose);

  return GoRouter(
    initialLocation: '/home',
    refreshListenable: refresh,
    redirect: (context, state) {
      final done = ref.read(onboardingDoneProvider);
      final loggedIn = ref.read(apiClientProvider).loggedIn;
      final path = state.matchedLocation;
      // Les pages d'authentification n'ont de sens que déconnecté ; les textes
      // légaux, eux, doivent rester lisibles dans les deux cas (on les ouvre
      // depuis l'inscription comme depuis le profil).
      final isAuthRoute = path == '/auth' || path == '/forgot';
      final isPublic = isAuthRoute || path.startsWith('/legal');

      if (!done) return path == '/onboarding' ? null : '/onboarding';
      if (!loggedIn) return isPublic ? null : '/auth';
      if (path == '/onboarding' || isAuthRoute) return '/home';
      // /ring a besoin de l'alarme passée en `extra` : sans elle (lien profond,
      // restauration d'état), l'écran planterait.
      if (path == '/ring' && state.extra is! AlarmItem) return '/home';
      return null;
    },
    routes: [
      GoRoute(path: '/onboarding', builder: (_, __) => const OnboardingPage()),
      GoRoute(path: '/auth', builder: (_, __) => const AuthPage()),
      GoRoute(path: '/forgot', builder: (_, __) => const ForgotPasswordPage()),
      GoRoute(path: '/home', builder: (_, __) => const HomeShell()),
      GoRoute(
        path: '/legal/:doc',
        builder: (_, state) => LegalPage(
          doc: state.pathParameters['doc'] == 'privacy' ? privacyDoc : termsDoc,
        ),
      ),
      GoRoute(path: '/moderation', builder: (_, __) => const ModerationPage()),
      GoRoute(path: '/verify', builder: (_, __) => const VerifyEmailPage()),
      GoRoute(
        path: '/ring',
        builder: (_, state) => RingPage(alarm: state.extra as AlarmItem),
      ),
    ],
    errorBuilder: (context, state) => Scaffold(
      backgroundColor: DingColors.paper,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.explore_off_outlined,
                    size: 40, color: DingColors.slate),
                const SizedBox(height: 16),
                Text(
                  'Cette page n’existe pas.',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                Text(
                  state.uri.toString(),
                  style: Theme.of(context).textTheme.bodySmall,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: 200,
                  child: FilledButton(
                    onPressed: () => context.go('/home'),
                    child: const Text('Retour à l’accueil'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
});
