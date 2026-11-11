import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config.dart';
import '../../core/providers.dart';
import '../../core/theme.dart';
import '../../core/widgets/hero_media.dart';
import '../../core/widgets/pill_button.dart';

class _Step {
  const _Step(this.title, this.body, this.image, this.alignment);
  final String title;
  final String body;
  final String image;

  /// Point d'intérêt de l'image : comme elle remplit maintenant un cadre
  /// portrait, `cover` recadre les côtés (ou le haut et le bas). Ça indique
  /// ce qu'on veut garder. Ces valeurs sont celles de la 0.2.1 : le cadrage
  /// des photos ne change pas.
  final Alignment alignment;
}

final _steps = <_Step>[
  const _Step(
    'Choisis en secret.',
    "Tu désignes les personnes qui t'intriguent. Personne n'est prévenu de ton choix.",
    'assets/images/onboarding_1.jpg',
    Alignment(0, 0),
  ),
  const _Step(
    'Sans réciprocité, rien ne se passe.',
    "Si l'autre ne t'a pas choisi, il ne saura jamais rien. Aucune gêne, aucune trace.",
    'assets/images/onboarding_2.jpg',
    Alignment(0, 0.2),
  ),
  const _Step(
    "Quand c'est réciproque et proche, ça sonne.",
    "À moins de ${Config.alarmRadiusMeters} m l'un de l'autre, les deux téléphones sonnent. Pour ça, Ding utilise ta position quand l'appli est ouverte.",
    'assets/images/onboarding_3.jpg',
    Alignment(0, -0.1),
  ),
];

class OnboardingPage extends ConsumerStatefulWidget {
  const OnboardingPage({super.key});

  @override
  ConsumerState<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends ConsumerState<OnboardingPage> {
  /// Hauteur de la barre du bas (hors zone système), partagée avec les pages
  /// pour qu'elles réservent la bonne place.
  static const _barHeight = 104.0;

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
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOutCubic,
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
    final safeBottom = MediaQuery.paddingOf(context).bottom;

    return Scaffold(
      backgroundColor: DingColors.paper,
      // La page ne défile pas : on plafonne donc l'agrandissement du texte
      // système, sinon un utilisateur à 200 % ferait déborder la mise en page.
      body: MediaQuery.withClampedTextScaling(
        maxScaleFactor: 1.25,
        child: Stack(
          children: [
            Positioned.fill(
              child: PageView.builder(
                controller: _controller,
                itemCount: _steps.length,
                onPageChanged: (i) => setState(() => _index = i),
                itemBuilder: (_, i) => _StepView(
                  step: _steps[i],
                  reservedBottom: _barHeight + safeBottom + 28,
                ),
              ),
            ),

            // « Passer » reste fixe pendant que les pages défilent.
            Positioned(
              top: 0,
              right: 0,
              child: SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.only(top: 8, right: 12),
                  child: _SkipButton(visible: !_last, onPressed: _finish),
                ),
              ),
            ),

            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: _BottomBar(
                index: _index,
                count: _steps.length,
                last: _last,
                onNext: _next,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Une page : l'image en pleine largeur, puis un fondu flou vers le papier
/// qui porte le texte. Le texte n'est jamais posé sur la photo : le contraste
/// reste bon quelle que soit l'image.
class _StepView extends StatelessWidget {
  const _StepView({required this.step, required this.reservedBottom});

  final _Step step;

  /// Place à laisser libre en bas (barre de boutons + marge).
  final double reservedBottom;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;

    return ColoredBox(
      color: DingColors.paper,
      child: Column(
        children: [
          // L'image prend toute la largeur et tout l'espace restant : elle
          // s'adapte à l'écran au lieu d'être enfermée dans un cadre.
          // (Le flou progressif et le fondu au papier sont dans HeroMedia,
          // partagé avec l'écran de connexion.)
          Expanded(
            child: HeroMedia(
              asset: step.image,
              alignment: step.alignment,
            ),
          ),

          Padding(
            padding: const EdgeInsets.fromLTRB(24, 4, 24, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(step.title, style: theme.headlineMedium),
                const SizedBox(height: 12),
                Text(step.body, style: theme.bodyLarge),
              ],
            ),
          ),

          // Réserve la place de la barre fixe (et de la zone système).
          SizedBox(height: reservedBottom),
        ],
      ),
    );
  }
}

class _SkipButton extends StatelessWidget {
  const _SkipButton({required this.visible, required this.onPressed});

  final bool visible;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      ignoring: !visible,
      child: AnimatedOpacity(
        opacity: visible ? 1 : 0,
        duration: const Duration(milliseconds: 200),
        // Sur la photo : papier translucide. (Sur le papier plein, la pastille
        // prend `mist` — voir l'écran de connexion.)
        child: PillButton(
          label: 'Passer',
          onPressed: onPressed,
          background: DingColors.paper.withValues(alpha: 0.85),
        ),
      ),
    );
  }
}

/// La barre du bas : trois segments qui disent où on en est, puis l'action.
/// Fixe (hors du PageView), elle ne bouge pas quand les pages glissent.
class _BottomBar extends StatelessWidget {
  const _BottomBar({
    required this.index,
    required this.count,
    required this.last,
    required this.onNext,
  });

  final int index;
  final int count;
  final bool last;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: DingColors.paper,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Semantics(
                label: 'Étape ${index + 1} sur $count',
                child: Row(
                  children: [
                    for (var i = 0; i < count; i++)
                      Expanded(
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 220),
                          curve: Curves.easeOut,
                          height: 3,
                          margin: EdgeInsets.only(
                            right: i == count - 1 ? 0 : 6,
                          ),
                          color: i <= index ? DingColors.ink : DingColors.mist,
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: onNext,
                child: Text(last ? 'Commencer' : 'Continuer'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
