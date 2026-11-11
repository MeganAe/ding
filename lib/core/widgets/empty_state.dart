import 'package:flutter/material.dart';

import '../theme.dart';

/// Un écran vide doit expliquer ce qui va s'y passer, pas afficher « vide ».
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.body,
    this.action,
  });

  final IconData icon;
  final String title;
  final String body;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              alignment: Alignment.center,
              decoration: const BoxDecoration(
                color: DingColors.mist,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 28, color: DingColors.ink),
            ),
            const SizedBox(height: 20),
            Text(title, style: theme.titleLarge, textAlign: TextAlign.center),
            const SizedBox(height: 8),
            Text(
              body,
              style: theme.bodyMedium?.copyWith(color: DingColors.slate),
              textAlign: TextAlign.center,
            ),
            if (action != null) ...[
              const SizedBox(height: 20),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}
