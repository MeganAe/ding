import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config.dart';
import '../../core/providers.dart';
import '../../core/theme.dart';

class _Step {
  const _Step(this.title, this.body, this.image, this.alignment);
  final String title;
  final String body;
  final String image;
  final Alignment alignment;
}

final _steps = <_Step>[
  const _Step(
    'Choisis en secret.',
    "Tu désignes les personnes qui t'intriguent. Personne n'est prévenu de ton choix.",
    'assets/images/onboarding_1.jpg',
    Alignment(0.4, 0),
  ),
  const _Step(
    "Sans réciprocité, rien ne se passe.",
    "Si l'autre ne t'a pas choisi, il ne saura jamais rien. Aucune gêne, aucune trace.",
    'assets/images/onboarding_2.jpg',
    Alignment(0, 0.4),
  ),
  _Step(
    "Quand c'est réciproque et proche, ça sonne.",
    "À moins de ${Config.alarmRadiusMeters} m l'un de l'autre, les deux téléphones sonnent. Pour ça, Ding utilise ta position quand l'appli est ouverte.",
    'assets/images/onboarding_3.jpg',
    const Alignment(0, -0.3),
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
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 24),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(20),
                            child: SizedBox.expand(
                              child: Image.asset(
                                step.image,
                                fit: BoxFit.cover,
                                alignment: step.alignment,
                                filterQuality: FilterQuality.high,
                              ),
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
