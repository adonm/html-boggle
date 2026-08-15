/// Themes: hand-built Adwaita (GNOME) plus the native Yaru (Ubuntu) themes,
/// with an easy runtime toggle persisted to localStorage.
///
/// Adwaita palette values are the libadwaita defaults:
///   https://gitlab.gnome.org/GNOME/libadwaita/-/blob/main/src/stylesheet/_defaults.scss
library;

import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:flutter/material.dart';
import 'package:yaru/yaru.dart';

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

  // libadwaita light defaults
  static const Color lightWindow = Color(0xFFFAFAFA);
  static const Color lightHeaderbar = Color(0xFFEBEBEB);
  static const Color lightText = Color(0xFF2E3436);

  // libadwaita dark defaults
  static const Color window = Color(0xFF242424);
  static const Color headerbar = Color(0xFF303030);
  static const Color card = Color(0xFF383838);
}

/// Adwaita radii: cards/entries 12 & 8 px, buttons are pills.
const double kAdwaitaCardRadius = 12;
const double kAdwaitaEntryRadius = 8;

/// The four built-in looks.
enum BoggleThemeMode { adwaitaDark, adwaitaLight, yaruDark, yaruLight }

extension BoggleThemeModeX on BoggleThemeMode {
  String get label => switch (this) {
        BoggleThemeMode.adwaitaDark => 'Adwaita Dark',
        BoggleThemeMode.adwaitaLight => 'Adwaita Light',
        BoggleThemeMode.yaruDark => 'Yaru Dark',
        BoggleThemeMode.yaruLight => 'Yaru Light',
      };
  bool get isYaru => this == BoggleThemeMode.yaruDark || this == BoggleThemeMode.yaruLight;
  bool get isLight => this == BoggleThemeMode.adwaitaLight || this == BoggleThemeMode.yaruLight;
}

/// Runtime theme switcher with localStorage persistence.
class ThemeController extends ChangeNotifier {
  ThemeController._() : _mode = _load();

  static final ThemeController instance = ThemeController._();

  static const _storageKey = 'boggle.themeMode';

  BoggleThemeMode _mode;

  BoggleThemeMode get mode => _mode;

  ThemeData get themeData => switch (_mode) {
        BoggleThemeMode.adwaitaDark => buildAdwaitaTheme(Brightness.dark),
        BoggleThemeMode.adwaitaLight => buildAdwaitaTheme(Brightness.light),
        BoggleThemeMode.yaruDark => yaruDark,
        BoggleThemeMode.yaruLight => yaruLight,
      };

  void setMode(BoggleThemeMode mode) {
    if (mode == _mode) return;
    _mode = mode;
    _persist(mode.name);
    notifyListeners();
  }

  static BoggleThemeMode _load() {
    try {
      final raw = _storage.callMethod<JSAny?>('getItem'.toJS, _storageKey.toJS);
      if (raw != null) {
        return BoggleThemeMode.values.asNameMap()[((raw as JSString).toDart)] ?? BoggleThemeMode.adwaitaDark;
      }
    } catch (_) {
      /* storage unavailable */
    }
    return BoggleThemeMode.adwaitaDark;
  }

  static void _persist(String? mode) {
    try {
      if (mode == null) {
        _storage.callMethod<JSAny?>('removeItem'.toJS, _storageKey.toJS);
      } else {
        _storage.callMethod<JSAny?>('setItem'.toJS, _storageKey.toJS, mode.toJS);
      }
    } catch (_) {
      /* storage unavailable */
    }
  }
}

@JS('window.localStorage')
external JSObject get _storage;

/// Build the Adwaita ThemeData for the given brightness.
ThemeData buildAdwaitaTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  const accent = AdwaitaColors.blue3;
  final window = dark ? AdwaitaColors.window : AdwaitaColors.lightWindow;
  final headerbar = dark ? AdwaitaColors.headerbar : AdwaitaColors.lightHeaderbar;
  final card = dark ? AdwaitaColors.card : AdwaitaColors.light1;
  final border = dark ? AdwaitaColors.dark2 : AdwaitaColors.light4;
  final text = dark ? AdwaitaColors.light1 : AdwaitaColors.lightText;
  final muted = dark ? AdwaitaColors.light5 : AdwaitaColors.dark2;

  final scheme = dark
      ? ColorScheme.dark(
          primary: accent,
          onPrimary: AdwaitaColors.light1,
          secondary: AdwaitaColors.blue2,
          onSecondary: AdwaitaColors.light1,
          error: AdwaitaColors.red2,
          onError: AdwaitaColors.light1,
          surface: window,
          onSurface: text,
          onSurfaceVariant: muted,
          outline: border,
          outlineVariant: dark ? AdwaitaColors.dark1 : AdwaitaColors.light3,
          surfaceContainerHighest: card,
        )
      : ColorScheme.light(
          primary: accent,
          onPrimary: AdwaitaColors.light1,
          secondary: AdwaitaColors.blue2,
          onSecondary: AdwaitaColors.light1,
          error: AdwaitaColors.red3,
          onError: AdwaitaColors.light1,
          surface: window,
          onSurface: text,
          onSurfaceVariant: muted,
          outline: border,
          outlineVariant: AdwaitaColors.light3,
          surfaceContainerHighest: headerbar,
        );

  const borderSide = BorderSide(color: AdwaitaColors.dark2);
  final borderSideResolved = dark ? borderSide : const BorderSide(color: AdwaitaColors.light4);
  final focusedBorder = BorderSide(color: accent, width: 2);

  final base = ThemeData(
    useMaterial3: true,
    brightness: brightness,
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
        color: muted,
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
        side: borderSideResolved,
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
        backgroundColor: dark ? card : AdwaitaColors.light2,
        foregroundColor: text,
        hoverColor: dark ? AdwaitaColors.dark1 : AdwaitaColors.light3,
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
      labelStyle: TextStyle(color: dark ? AdwaitaColors.light4 : AdwaitaColors.dark2),
      hintStyle: TextStyle(color: muted),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(kAdwaitaEntryRadius),
        borderSide: borderSideResolved,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(kAdwaitaEntryRadius),
        borderSide: borderSideResolved,
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
      backgroundColor: headerbar,
      contentTextStyle: TextStyle(color: text),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(kAdwaitaCardRadius),
      ),
      behavior: SnackBarBehavior.floating,
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      linearTrackColor: headerbar,
      circularTrackColor: headerbar,
    ),
    chipTheme: base.chipTheme.copyWith(
      backgroundColor: card,
      shape: const StadiumBorder(side: BorderSide.none),
      labelStyle: TextStyle(color: text, fontSize: 12),
    ),
    dividerTheme: DividerThemeData(
      color: border,
      thickness: 1,
    ),
    listTileTheme: ListTileThemeData(
      iconColor: muted,
      textColor: text,
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: headerbar,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(kAdwaitaCardRadius),
      ),
    ),
  );
}
