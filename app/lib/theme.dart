/// Adwaita theme - GNOME's design system (libadwaita), built by hand for
/// close alignment:
///   https://gitlab.gnome.org/GNOME/libadwaita/-/blob/main/src/stylesheet/_defaults.scss
///
/// Palette values are the libadwaita defaults (dark: window #242424,
/// headerbar #303030, card #383838, accent blue #3584e4).
library;

import 'package:flutter/material.dart';

/// The libadwaita accent scales (dark variants, used as-is).
class AdwaitaColors {
  static const Color blue1 = Color(0xFF99C1F1);
  static const Color blue2 = Color(0xFF62A0EA);
  static const Color blue3 = Color(0xFF3584E4);
  static const Color blue4 = Color(0xFF1C71D8);
  static const Color blue5 = Color(0xFF1A5FB4);

  static const Color green3 = Color(0xFF33D17A);
  static const Color green4 = Color(0xFF2EC27E);
  static const Color green5 = Color(0xFF26A269);

  static const Color yellow4 = Color(0xFFF5C211);
  static const Color yellow5 = Color(0xFFE5A50A);

  static const Color orange3 = Color(0xFFFF7800);

  static const Color red2 = Color(0xFFED333B);
  static const Color red3 = Color(0xFFE01B24);
  static const Color red4 = Color(0xFFC01C28);

  static const Color light1 = Color(0xFFFFFFFF);
  static const Color light2 = Color(0xFFF6F5F4);
  static const Color light3 = Color(0xFFDEDDDA);
  static const Color light4 = Color(0xFFC0BFBC);
  static const Color light5 = Color(0xFF9A9996);

  static const Color dark1 = Color(0xFF77767B);
  static const Color dark2 = Color(0xFF5E5C64);
  static const Color dark3 = Color(0xFF3D3846);

  /// libadwaita dark window background.
  static const Color window = Color(0xFF242424);

  /// libadwaita dark header bar background.
  static const Color headerbar = Color(0xFF303030);

  /// libadwaita dark card background.
  static const Color card = Color(0xFF383838);
}

/// Adwaita radii: cards/entries 12 & 8 px, buttons are pills.
const double kAdwaitaCardRadius = 12;
const double kAdwaitaEntryRadius = 8;

/// Build the Adwaita dark ThemeData.
ThemeData buildAdwaitaTheme() {
  const accent = AdwaitaColors.blue3;
  const window = AdwaitaColors.window;
  const card = AdwaitaColors.card;
  const border = AdwaitaColors.dark2;

  final scheme = ColorScheme.dark(
    primary: accent,
    onPrimary: AdwaitaColors.light1,
    secondary: AdwaitaColors.blue2,
    onSecondary: AdwaitaColors.light1,
    error: AdwaitaColors.red2,
    onError: AdwaitaColors.light1,
    surface: window,
    onSurface: AdwaitaColors.light1,
    onSurfaceVariant: AdwaitaColors.light5,
    outline: border,
    outlineVariant: AdwaitaColors.dark1,
    surfaceContainerHighest: card,
  );

  const borderSide = BorderSide(color: border);
  const focusedBorder = BorderSide(color: accent, width: 2);

  final base = ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: scheme,
    scaffoldBackgroundColor: window,
    // NOTE: no custom fontFamily on web - a missing family makes the text
    // reflow asynchronously, which destabilizes the semantics DOM.
  );

  return base.copyWith(
    textTheme: base.textTheme.copyWith(
      displaySmall: base.textTheme.displaySmall?.copyWith(
        fontSize: 26,
        fontWeight: FontWeight.w700,
      ),
      headlineMedium: base.textTheme.headlineMedium?.copyWith(
        fontSize: 20,
        fontWeight: FontWeight.w700,
      ),
      headlineSmall: base.textTheme.headlineSmall?.copyWith(
        fontSize: 24,
        fontWeight: FontWeight.w700,
      ),
      titleLarge: base.textTheme.titleLarge?.copyWith(
        fontSize: 18,
        fontWeight: FontWeight.w700,
      ),
      titleMedium: base.textTheme.titleMedium?.copyWith(
        fontSize: 16,
        fontWeight: FontWeight.w600,
      ),
      bodyMedium: base.textTheme.bodyMedium?.copyWith(fontSize: 14),
      bodySmall: base.textTheme.bodySmall?.copyWith(
        fontSize: 13,
        color: AdwaitaColors.light5,
      ),
      labelMedium: base.textTheme.labelMedium?.copyWith(
        fontSize: 12,
        fontWeight: FontWeight.w600,
      ),
    ),
    // Buttons are pills in Adwaita.
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        shape: const StadiumBorder(),
        textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        shape: const StadiumBorder(),
        side: borderSide,
        textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        shape: const StadiumBorder(),
        textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        backgroundColor: card,
        foregroundColor: AdwaitaColors.light1,
        hoverColor: AdwaitaColors.dark1,
      ),
    ),
    // Cards: 12px rounded, headerbar-toned surfaces.
    cardTheme: CardThemeData(
      color: card,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(kAdwaitaCardRadius),
      ),
      margin: EdgeInsets.zero,
    ),
    // Entries: filled, 8px rounded, 1px border; accent border on focus.
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: card,
      floatingLabelBehavior: FloatingLabelBehavior.never,
      labelStyle: const TextStyle(color: AdwaitaColors.light4),
      hintStyle: const TextStyle(color: AdwaitaColors.light5),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(kAdwaitaEntryRadius),
        borderSide: borderSide,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(kAdwaitaEntryRadius),
        borderSide: borderSide,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(kAdwaitaEntryRadius),
        borderSide: focusedBorder,
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(kAdwaitaEntryRadius),
        borderSide: const BorderSide(color: AdwaitaColors.red2),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: AdwaitaColors.headerbar,
      contentTextStyle: const TextStyle(color: AdwaitaColors.light1),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(kAdwaitaCardRadius),
      ),
      behavior: SnackBarBehavior.floating,
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      linearTrackColor: AdwaitaColors.headerbar,
      circularTrackColor: AdwaitaColors.headerbar,
    ),
    chipTheme: base.chipTheme.copyWith(
      backgroundColor: card,
      shape: const StadiumBorder(side: BorderSide.none),
      labelStyle: const TextStyle(color: AdwaitaColors.light1, fontSize: 12),
    ),
    dividerTheme: const DividerThemeData(
      color: AdwaitaColors.dark2,
      thickness: 1,
    ),
    listTileTheme: const ListTileThemeData(
      iconColor: AdwaitaColors.light5,
      textColor: AdwaitaColors.light1,
    ),
  );
}
