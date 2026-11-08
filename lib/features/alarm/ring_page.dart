import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../core/rings.dart';
import '../../core/theme.dart';
import '../../data/models.dart';

/// L'écran qui sonne : le seul moment animé de l'app.
class RingPage extends StatefulWidget {
  const RingPage({super.key, required this.alarm});
  final AlarmItem alarm;

  @override
  State<RingPage> createState() => _RingPageState();
}

class _RingPageState extends State<RingPage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2600),
  );
  Timer? _haptics;
  int _beats = 0;
  bool _started = false;

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
    _haptics = Timer.periodic(const Duration(milliseconds: 800), (t) {
      HapticFeedback.heavyImpact();
      if (++_beats >= 6) t.cancel();
    });
  }

  @override
  void dispose() {
    _haptics?.cancel();
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
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
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Spacer(),
                  Text('${widget.alarm.otherName} est tout près.',
                      style: onSignal),
                  const SizedBox(height: 16),
                  Text(
                    'Vous vous êtes choisis. Levez les yeux.',
                    style: theme.bodyLarge?.copyWith(color: DingColors.paper),
                  ),
                  const SizedBox(height: 32),
                  FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: DingColors.paper,
                      foregroundColor: DingColors.ink,
                    ),
                    onPressed: () => context.pop(),
                    child: const Text('Fermer'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
