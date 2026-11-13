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
    Widget image() => Image.asset(
          asset,
          fit: BoxFit.cover,
          alignment: alignment,
          filterQuality: FilterQuality.medium,
          cacheWidth: cacheWidth,
        );

    // Version floue, sans filtre d'image GPU.
    //
    // On décode l'image à 40 px de large et on la laisse être agrandie :
    // l'interpolation fait tout le travail. C'était d'abord un
    // `ImageFilter.blur` (sigma 18), mais sur les téléphones qui n'ont pas
    // Vulkan — Android 8 et 9, donc le parc visé — le rendu du flou passait
    // par le chemin OpenGL ES et laissait un liseré noir à la jonction avec le
    // papier. Un décodage minuscule donne le même fondu, coûte moins cher, et
    // se comporte pareil sur tous les téléphones.
    Widget blurred() => Image.asset(
          asset,
          fit: BoxFit.cover,
          alignment: alignment,
          filterQuality: FilterQuality.low,
          cacheWidth: 40,
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
            child: blurred(),
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
