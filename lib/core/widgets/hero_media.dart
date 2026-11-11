import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// Le motif visuel de Ding : une photo pleine largeur qui se dissout dans le
/// papier par un flou progressif.
///
/// Partagé par l'onboarding et par l'écran de connexion, pour que les deux
/// racontent la même chose. Le widget remplit l'espace que son parent lui
/// donne : c'est à l'appelant de fixer la hauteur.
class HeroMedia extends StatelessWidget {
  const HeroMedia({
    super.key,
    required this.asset,
    this.alignment = Alignment.center,
    this.cacheWidth,
    this.showTopVeil = true,
  });

  final String asset;

  /// Point d'intérêt : en `cover`, l'image est recadrée pour remplir le cadre.
  final Alignment alignment;

  /// Largeur de décodage. À laisser nul quand les sources sont petites :
  /// décoder plus grand n'ajoute aucun détail et coûte de la mémoire.
  final int? cacheWidth;

  /// Voile clair en haut, pour garder la barre d'état et un bouton flottant
  /// lisibles sur une photo claire.
  final bool showTopVeil;

  @override
  Widget build(BuildContext context) {
    // Deux widgets distincts, mais le même asset : Flutter ne décode l'image
    // qu'une fois et la partage entre les deux couches.
    Widget image() => Image.asset(
          asset,
          fit: BoxFit.cover,
          alignment: alignment,
          filterQuality: FilterQuality.medium,
          cacheWidth: cacheWidth,
        );

    // `SizedBox.expand` : le widget prend tout l'espace offert même quand ses
    // contraintes sont lâches (par exemple dans un AnimatedSwitcher).
    return SizedBox.expand(
      child: Stack(
        fit: StackFit.expand,
        children: [
          image(),

          // Copie floutée de la même image, révélée par un dégradé : le
          // passage du net au flou est donc progressif, sans bord visible.
          // (Un BackdropFilter donnerait une bande au bord net, et coûte un
          // rendu de l'arrière-plan à chaque image.)
          ShaderMask(
            blendMode: BlendMode.dstIn,
            shaderCallback: (rect) => const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Color(0x00FFFFFF),
                Color(0x00FFFFFF),
                Color(0x59FFFFFF),
                Color(0xD9FFFFFF),
                Color(0xFFFFFFFF),
              ],
              stops: [0.0, 0.58, 0.75, 0.90, 1.0],
            ).createShader(rect),
            child: ImageFiltered(
              imageFilter: ui.ImageFilter.blur(
                sigmaX: 18,
                sigmaY: 18,
                tileMode: ui.TileMode.clamp,
              ),
              child: image(),
            ),
          ),

          // Voile de papier : finit en aplat, pour que le contenu posé juste
          // dessous soit sur la même surface que l'image.
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color(0x00F3F5F9),
                  Color(0x00F3F5F9),
                  Color(0x59F3F5F9),
                  Color(0xE6F3F5F9),
                  Color(0xFFF3F5F9),
                ],
                stops: [0.0, 0.55, 0.73, 0.90, 1.0],
              ),
            ),
          ),

          if (showTopVeil)
            const Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: 120,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0x80F3F5F9), Color(0x00F3F5F9)],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
