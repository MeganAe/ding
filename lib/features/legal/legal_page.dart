import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme.dart';
import 'legal_texts.dart';

/// Affiche un document légal ([termsDoc] ou [privacyDoc]).
///
/// Mise en page volontairement sobre — pas de carte paragraphe, pas de couleur
/// d'accent : un texte qu'on doit pouvoir lire en entier sans être distrait.
class LegalPage extends StatelessWidget {
  const LegalPage({super.key, required this.doc});

  final LegalDoc doc;

  void _back(BuildContext context) {
    // Ouverte depuis l'inscription (pas d'historique) comme depuis le profil :
    // on retombe sur l'accueil dans le second cas.
    final router = GoRouter.maybeOf(context);
    if (router != null && router.canPop()) {
      router.pop();
      return;
    }
    Navigator.maybePop(context);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;

    return Scaffold(
      backgroundColor: DingColors.paper,
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 40),
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: IconButton(
                tooltip: 'Retour',
                padding: EdgeInsets.zero,
                alignment: Alignment.centerLeft,
                icon: const Icon(Icons.arrow_back, color: DingColors.ink),
                onPressed: () => _back(context),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'DING · DOCUMENT LÉGAL',
              style: theme.bodySmall?.copyWith(
                letterSpacing: 1.2,
                fontWeight: FontWeight.w600,
                color: DingColors.slate,
              ),
            ),
            const SizedBox(height: 8),
            Text(doc.title, style: theme.headlineMedium),
            const SizedBox(height: 12),
            Text(doc.subtitle, style: theme.bodyMedium),
            const SizedBox(height: 16),
            Align(
              alignment: Alignment.centerLeft,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: DingColors.mist,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  'Version $legalVersion',
                  style: theme.bodySmall?.copyWith(color: DingColors.ink),
                ),
              ),
            ),
            const SizedBox(height: 28),
            for (final section in doc.sections) _Section(section: section),
            const SizedBox(height: 8),
            const _ContactCard(),
          ],
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.section});

  final LegalSection section;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: 26),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            section.title,
            style: theme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 10),
          for (final p in section.paragraphs)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Text(
                p,
                style: theme.bodyMedium?.copyWith(height: 1.55),
              ),
            ),
          for (final b in section.bullets)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Un tiret, pas une puce ronde : plus calme à lire, et
                  // aligné sur le reste de l'app.
                  Padding(
                    padding: const EdgeInsets.only(top: 1, right: 10),
                    child: Text('—', style: theme.bodyMedium),
                  ),
                  Expanded(
                    child: Text(
                      b,
                      style: theme.bodyMedium?.copyWith(height: 1.55),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _ContactCard extends StatelessWidget {
  const _ContactCard();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Une question, une contestation ?',
              style: theme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            Text(
              'Écris à $contactEmail. On répond, même pour dire qu’on ne sait '
              'pas encore.',
              style: theme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}
