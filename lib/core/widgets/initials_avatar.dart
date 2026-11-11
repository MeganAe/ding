import 'package:flutter/material.dart';

import '../theme.dart';

/// Une pastille avec l'initiale d'un prénom.
///
/// C'est l'avatar de toute l'app : pas de photo de profil (personne ne veut
/// mettre son visage dans une app de crushs secrets), juste une lettre. La
/// teinte change avec le prénom pour que deux lignes voisines se distinguent.
class InitialsAvatar extends StatelessWidget {
  const InitialsAvatar({
    super.key,
    required this.name,
    this.radius = 22,
    this.highlight = false,
  });

  final String name;
  final double radius;

  /// Variante « signal » : utilisée sur l'écran qui sonne.
  final bool highlight;

  static const _tints = [
    Color(0xFFE7ECF6),
    Color(0xFFF6E9E4),
    Color(0xFFE4EFE8),
    Color(0xFFF1E7F2),
    Color(0xFFEAF0DE),
    Color(0xFFF7EAD9),
  ];

  String get _initial {
    final n = name.trim();
    if (n.isEmpty) return '?';
    // `runes` plutôt que `[0]` : un prénom peut commencer par un emoji ou un
    // caractère hors du plan de base, qui tiendrait sur deux unités UTF-16.
    return String.fromCharCode(n.runes.first).toUpperCase();
  }

  Color get _background {
    if (highlight) return DingColors.paper;
    if (name.trim().isEmpty) return DingColors.mist;
    // Somme des codes : stable pour un même prénom, répartie entre les teintes.
    final sum = name.trim().codeUnits.fold<int>(0, (a, b) => a + b);
    return _tints[sum % _tints.length];
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: radius * 2,
      height: radius * 2,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: _background, shape: BoxShape.circle),
      child: Text(
        _initial,
        style: TextStyle(
          fontFamily: Theme.of(context).textTheme.titleMedium?.fontFamily,
          fontWeight: FontWeight.w600,
          fontSize: radius * 0.8,
          color: highlight ? DingColors.signal : DingColors.ink,
          height: 1,
        ),
      ),
    );
  }
}
