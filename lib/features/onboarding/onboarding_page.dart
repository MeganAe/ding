import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config.dart';
import '../../core/providers.dart';
import '../../core/rings.dart';
import '../../core/theme.dart';

class _Step {
  const _Step(this.title, this.body, this.sources);
  final String title;
  final String body;
  final List<RingSource> sources;
}

final _steps = <_Step>[
  const _Step(
    'Choisis en secret.',
    "Tu désignes les personnes qui t'intriguent. Personne n'est prévenu de ton choix.",
    [RingSource(0.5, 0.5, 5, DingColors.signal)],
  ),
  const _Step(
    "Sans réciprocité, rien ne se passe.",
    "Si l'autre ne t'a pas choisi, il ne saura jamais rien. Aucune gêne, aucune trace.",
    [
      RingSource(0.28, 0.5, 3, DingColors.signal),
      RingSource(0.74, 0.5, 0, DingColors.slate),
    ],
  ),
  _Step(
    "Quand c'est réciproque et proche, ça sonne.",
    "À moins de ${Config.alarmRadiusMeters} m l'un de l'autre, les deux téléphones sonnent. Pour ça, Ding utilise ta position quand l'appli est ouverte.",
    const [
      RingSource(0.36, 0.5, 4, DingColors.signal),
      RingSource(0.64, 0.5, 4, DingColors.ink),
    ],
  ),
];

class OnboardingPage extends ConsumerStatefulWidget {
  const OnboardingPage({super.key});

  @override
  ConsumerState<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends ConsumerState<OnboardingPage> {
  final _controller = PageController();
  int _index = 0;

  bool get _last => _index == _steps.length - 1;

  Future<void> _finish() async {
    await ref.read(prefsProvider).setBool('onboarding_done', true);
    ref.read(onboardingDoneProvider.notifier).state = true;
  }

  void _next() {
    if (_last) {
      _finish();
    } else {
      _controller.nextPage(
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOut,
      );
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            SizedBox(
              height: 56,
              child: Align(
                alignment: Alignment.centerRight,
                child: _last
                    ? null
                    : Padding(
                        padding: const EdgeInsets.only(right: 12),
                        child: TextButton(
                          onPressed: _finish,
                          child: const Text('Passer'),
                        ),
                      ),
              ),
            ),
            Expanded(
              child: PageView.builder(
                controller: _controller,
                itemCount: _steps.length,
                onPageChanged: (i) => setState(() => _index = i),
                itemBuilder: (_, i) {
                  final step = _steps[i];
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: ClipRect(
                          child: SizedBox.expand(
                            child: CustomPaint(
                              painter: RingsPainter(step.sources),
                            ),
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(step.title, style: theme.headlineMedium),
                            const SizedBox(height: 12),
                            Text(step.body, style: theme.bodyLarge),
                          ],
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
              child: Column(
                children: [
                  Row(
                    children: [
                      for (var i = 0; i < _steps.length; i++)
                        Expanded(
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            height: 3,
                            margin: EdgeInsets.only(
                              right: i == _steps.length - 1 ? 0 : 6,
                            ),
                            color: i <= _index
                                ? DingColors.ink
                                : DingColors.mist,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  FilledButton(
                    onPressed: _next,
                    child: Text(_last ? 'Commencer' : 'Continuer'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
