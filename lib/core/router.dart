import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/models.dart';
import '../features/alarm/ring_page.dart';
import '../features/auth/auth_page.dart';
import '../features/home/home_shell.dart';
import '../features/onboarding/onboarding_page.dart';
import 'providers.dart';

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
      final loggedIn = Supabase.instance.client.auth.currentSession != null;
      final path = state.matchedLocation;

      if (!done) return path == '/onboarding' ? null : '/onboarding';
      if (!loggedIn) return path == '/auth' ? null : '/auth';
      if (path == '/onboarding' || path == '/auth') return '/home';
      return null;
    },
    routes: [
      GoRoute(path: '/onboarding', builder: (_, __) => const OnboardingPage()),
      GoRoute(path: '/auth', builder: (_, __) => const AuthPage()),
      GoRoute(path: '/home', builder: (_, __) => const HomeShell()),
      GoRoute(
        path: '/ring',
        builder: (_, state) => RingPage(alarm: state.extra as AlarmItem),
      ),
    ],
  );
});
