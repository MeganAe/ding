import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers.dart';
import '../alarm/alarms_page.dart';
import '../discover/discover_page.dart';
import '../profile/profile_page.dart';

class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key});

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell> {
  int _tab = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _sendLocation();
    _timer = Timer.periodic(const Duration(minutes: 2), (_) => _sendLocation());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  /// V1 : la position est envoyée uniquement quand l'appli est ouverte.
  Future<void> _sendLocation() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) return;
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        return;
      }
      final pos = await Geolocator.getCurrentPosition(
        locationSettings:
            const LocationSettings(accuracy: LocationAccuracy.medium),
      );
      if (!mounted) return;
      await ref.read(repositoryProvider).sendLocation(
            pos.latitude,
            pos.longitude,
          );
    } catch (_) {
      // Pas de position : on réessaiera au prochain cycle.
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(alarmsProvider, (prev, next) {
      final list = next.valueOrNull;
      if (list == null) return;
      final seen = ref.read(seenAlarmsProvider);
      final firstLoad = prev?.valueOrNull == null;
      final fresh = list.where((a) => !seen.contains(a.id)).toList();

      ref.read(seenAlarmsProvider.notifier).state = {
        ...seen,
        ...list.map((a) => a.id),
      };
      if (!firstLoad && fresh.isNotEmpty) {
        context.push('/ring', extra: fresh.first);
      }
    });

    return Scaffold(
      body: IndexedStack(
        index: _tab,
        children: const [DiscoverPage(), AlarmsPage(), ProfilePage()],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.favorite_border),
            selectedIcon: Icon(Icons.favorite),
            label: 'Découvrir',
          ),
          NavigationDestination(
            icon: Icon(Icons.notifications_none),
            selectedIcon: Icon(Icons.notifications),
            label: 'Alarmes',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person),
            label: 'Profil',
          ),
        ],
      ),
    );
  }
}
