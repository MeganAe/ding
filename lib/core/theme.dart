import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Palette : un papier froid, une encre bleu nuit, et un seul rouge
/// réservé à l'alarme. Pas de dégradé, pas d'ombre.
class DingColors {
  static const paper = Color(0xFFF3F5F9);
  static const ink = Color(0xFF161A2E);
  // Assombri depuis #E5383B : le texte clair sur ce rouge atteignait
  // 3,88:1, sous le seuil AA (4,5:1) pour du texte de 16 px.
  // #D32F2F donne 4,56:1 avec `paper`, sans changer le caractère.
  static const signal = Color(0xFFD32F2F);
  static const mist = Color(0xFFDDE3EE);
  static const slate = Color(0xFF5B6378);
  // Surfaces : les cartes se détachent du papier par un blanc très légèrement
  // froid et un filet, jamais par une ombre (la palette n'a pas d'ombre).
  static const card = Color(0xFFFFFFFF);
  static const line = Color(0xFFE3E8F1);
}

ThemeData buildTheme() {
  const c = DingColors.ink;
  final base = ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    scaffoldBackgroundColor: DingColors.paper,
    colorScheme: const ColorScheme.light(
      primary: DingColors.ink,
      onPrimary: DingColors.paper,
      secondary: DingColors.signal,
      surface: DingColors.paper,
      onSurface: DingColors.ink,
      error: DingColors.signal,
    ),
  );

  final body = GoogleFonts.instrumentSansTextTheme(base.textTheme)
      .apply(bodyColor: c, displayColor: c);

  TextStyle head(double size, {double h = 1.1, double ls = -0.5}) =>
      GoogleFonts.bricolageGrotesque(
        fontSize: size,
        fontWeight: FontWeight.w700,
        height: h,
        letterSpacing: ls,
        color: c,
      );

  final text = body.copyWith(
    displayLarge: head(40, h: 1.05, ls: -1),
    headlineMedium: head(28),
    titleLarge: head(22, h: 1.2, ls: -0.3),
    titleMedium: body.titleMedium?.copyWith(fontWeight: FontWeight.w600),
    bodyLarge: body.bodyLarge?.copyWith(fontSize: 16, height: 1.45),
    bodyMedium: body.bodyMedium?.copyWith(fontSize: 15, height: 1.45),
    bodySmall: body.bodySmall
        ?.copyWith(fontSize: 13, height: 1.4, color: DingColors.slate),
  );

  final shape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(14));
  final cardShape = RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(18),
    side: const BorderSide(color: DingColors.line),
  );

  return base.copyWith(
    textTheme: text,
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: DingColors.ink,
        foregroundColor: DingColors.paper,
        minimumSize: const Size.fromHeight(54),
        shape: shape,
        textStyle: text.titleMedium,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: DingColors.ink,
        side: const BorderSide(color: DingColors.ink, width: 1.2),
        minimumSize: const Size.fromHeight(54),
        shape: shape,
        textStyle: text.titleMedium,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: DingColors.ink,
        textStyle: text.titleMedium,
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: DingColors.mist,
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      hintStyle: text.bodyMedium?.copyWith(color: DingColors.slate),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: DingColors.ink, width: 1.5),
      ),
    ),
    cardTheme: CardThemeData(
      color: DingColors.card,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: cardShape,
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: DingColors.paper,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      titleTextStyle: text.titleLarge,
      contentTextStyle: text.bodyMedium,
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: DingColors.paper,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
    ),
    dividerTheme: const DividerThemeData(
      color: DingColors.line,
      thickness: 1,
      space: 1,
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: DingColors.ink,
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: DingColors.paper,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      indicatorColor: DingColors.mist,
      labelTextStyle: WidgetStatePropertyAll(text.bodySmall?.copyWith(
        color: DingColors.ink,
        fontWeight: FontWeight.w600,
      )),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: DingColors.ink,
      contentTextStyle: text.bodyMedium?.copyWith(color: DingColors.paper),
      shape: shape,
    ),
  );
}
