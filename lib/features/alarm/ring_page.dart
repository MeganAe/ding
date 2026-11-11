import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers.dart';
import '../../core/rings.dart';
import '../../core/theme.dart';
import '../../core/widgets/initials_avatar.dart';
import '../../data/models.dart';

/// L'écran qui sonne : le seul moment animé de l'app.
class RingPage extends ConsumerStatefulWidget {
  const RingPage({super.key, required this.alarm});
  final AlarmItem alarm;

  @override
  ConsumerState<RingPage> createState() => _RingPageState();
}

class _RingPageState extends ConsumerState<RingPage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2600),
  );
  final _player = AudioPlayer();
  Timer? _haptics;
  int _beats = 0;
  bool _started = false;
  bool _soundOn = true;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;

    if (MediaQuery.disableAnimationsOf(context)) {
      _c.value = 0.35;
    } else {
      _c.repeat();
    }
    _startSound();
    _startHaptics();
  }

  /// Le son vient d'un fichier embarqué (assets/audio/ding.wav) : il fonctionne
  /// hors ligne et sans dépendre du téléphone. Sans ça, l'écran ne vibrait que
  /// si l'appli était au premier plan, ce qui n'est pas une alarme.
  Future<void> _startSound() async {
    try {
      await _player.setReleaseMode(ReleaseMode.loop);
      await _player.setVolume(1);
      await _player.play(AssetSource('audio/ding.wav'));
    } catch (_) {
      // Audio indisponible : l'alarme reste visible et vibrante.
    }
  }

  void _startHaptics() {
    HapticFeedback.heavyImpact();
    _haptics = Timer.periodic(const Duration(milliseconds: 800), (t) {
      HapticFeedback.heavyImpact();
      if (++_beats >= 6) t.cancel();
    });
  }

  Future<void> _silence() async {
    _haptics?.cancel();
    try {
      await _player.stop();
    } catch (_) {
      // Rien à couper (le son n'avait pas démarré).
    }
    if (mounted) setState(() => _soundOn = false);
  }

  void _close() {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/home');
    }
  }

  @override
  void dispose() {
    _haptics?.cancel();
    _c.dispose();
    unawaited(_player.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    final radius = ref.watch(alarmRadiusProvider);
    final name =
        widget.alarm.otherName.isEmpty ? 'Quelqu’un' : widget.alarm.otherName;

    final onSignal = theme.displayLarge?.copyWith(color: DingColors.paper);

    return Scaffold(
      backgroundColor: DingColors.signal,
      body: Stack(
        children: [
          Positioned.fill(
            child: AnimatedBuilder(
              animation: _c,
              builder: (_, __) => CustomPaint(painter: PulsePainter(_c.value)),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Spacer(),
                  // L'initiale, posée au centre des ondes.
                  InitialsAvatar(name: name, radius: 34, highlight: true),
                  const SizedBox(height: 24),
                  Text('$name est tout près.', style: onSignal),
                  const SizedBox(height: 12),
                  Text(
                    'Vous vous êtes choisis. Levez les yeux.',
                    style: theme.bodyLarge?.copyWith(color: DingColors.paper),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    [
                      'à moins de $radius m',
                      if (widget.alarm.otherFaculty != null &&
                          widget.alarm.otherFaculty!.isNotEmpty)
                        widget.alarm.otherFaculty!,
                    ].join(' · '),
                    style: theme.bodySmall?.copyWith(
                      color: DingColors.paper.withValues(alpha: 0.85),
                    ),
                  ),
                  const SizedBox(height: 32),
                  FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: DingColors.paper,
                      foregroundColor: DingColors.ink,
                    ),
                    onPressed: _close,
                    child: const Text('J’y vais'),
                  ),
                  if (_soundOn) ...[
                    const SizedBox(height: 8),
                    Center(
                      child: TextButton(
                        style: TextButton.styleFrom(
                          foregroundColor: DingColors.paper,
                        ),
                        onPressed: _silence,
                        child: const Text('Couper le son'),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
