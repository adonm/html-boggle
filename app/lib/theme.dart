/// Yaru-native theming: Ubuntu's design system with switchable accent
/// variants and brightness, persisted to localStorage.
library;

import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:flutter/material.dart';
import 'package:yaru/yaru.dart';

/// Fixed colors for game chrome (independent of the chosen variant).
class BoggleColors {
  static const Color medalGold = Color(0xFFE5A50A);
  static const Color medalSilver = Color(0xFFC0BFBC);
  static const Color medalBronze = Color(0xFFFF7800);
  static const Color youGreen = Color(0xFF3EB34F);
}

/// Runtime theme switcher: Yaru accent variant x dark/light, persisted.
class ThemeController extends ChangeNotifier {
  ThemeController._()
      : _variant = _loadVariant(),
        _light = _loadLight();

  static final ThemeController instance = ThemeController._();

  static const _variantKey = 'boggle.themeVariant';
  static const _lightKey = 'boggle.themeLight';

  YaruVariant _variant;
  bool _light;

  YaruVariant get variant => _variant;
  bool get light => _light;

  /// The current Yaru ThemeData.
  ThemeData get themeData => _light ? _variant.theme : _variant.darkTheme;

  /// The available accent colors (the Yaru accent palette).
  List<YaruVariant> get accents => YaruVariant.accents;

  void setVariant(YaruVariant variant) {
    if (variant == _variant) return;
    _variant = variant;
    _persist();
    notifyListeners();
  }

  void setLight(bool light) {
    if (light == _light) return;
    _light = light;
    _persist();
    notifyListeners();
  }

  void _persist() {
    try {
      _storage.callMethod<JSAny?>('setItem'.toJS, _variantKey.toJS, _variant.name.toJS);
      _storage.callMethod<JSAny?>('setItem'.toJS, _lightKey.toJS, _light ? '1'.toJS : '0'.toJS);
    } catch (_) {
      /* storage unavailable */
    }
  }

  static YaruVariant _loadVariant() {
    try {
      final raw = _storage.callMethod<JSAny?>('getItem'.toJS, _variantKey.toJS);
      if (raw != null) {
        final name = (raw as JSString).toDart;
        return YaruVariant.values.asNameMap()[name] ?? YaruVariant.orange;
      }
    } catch (_) {
      /* storage unavailable */
    }
    return YaruVariant.orange;
  }

  static bool _loadLight() {
    try {
      final raw = _storage.callMethod<JSAny?>('getItem'.toJS, _lightKey.toJS);
      if (raw != null) return (raw as JSString).toDart == '1';
    } catch (_) {
      /* storage unavailable */
    }
    return false;
  }
}

@JS('window.localStorage')
external JSObject get _storage;
