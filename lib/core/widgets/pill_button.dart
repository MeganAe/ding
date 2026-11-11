import 'package:flutter/material.dart';

import '../theme.dart';

/// Une action secondaire, posée comme une pastille de papier.
///
/// Même forme que le « Passer » de l'onboarding, pour que les écrans
/// racontent la même chose : une seule action pleine (le bouton encre), et
/// tout le reste en pastilles discrètes.
class PillButton extends StatelessWidget {
  const PillButton({
    super.key,
    required this.label,
    this.onPressed,
    this.background,
    this.foreground,
  });

  final String label;
  final VoidCallback? onPressed;

  /// Par défaut `mist` (sur le papier). L'onboarding passe du papier
  /// translucide, la pastille étant posée sur une photo.
  final Color? background;
  final Color? foreground;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    final color = enabled
        ? (foreground ?? DingColors.ink)
        : DingColors.slate.withValues(alpha: 0.6);

    return Material(
      color: background ?? DingColors.mist,
      shape: const StadiumBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onPressed,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontSize: 14, color: color),
          ),
        ),
      ),
    );
  }
}
