/// Tiny sound manager: one pooled player per bundled effect. Sounds are
/// synthesized WAVs (scripts/gen_sfx.ts), played locally - never synced.
/// Muted state persists in localStorage.
library;

import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:audioplayers/audioplayers.dart';

@JS('window.localStorage')
external JSObject get _storage;

class Sfx {
  static const List<String> _names = [
    'start', 'tick', 'tap', 'success', 'fail', 'win', 'end',
  ];

  static final Map<String, AudioPool> _pools = {};
  static bool _ready = false;

  static bool get muted {
    try {
      final raw = _storage.callMethod<JSAny?>('getItem'.toJS, 'boggle.muted'.toJS);
      return raw is JSString && raw.toDart == '1';
    } catch (_) {
      return false;
    }
  }

  static void setMuted(bool m) {
    try {
      _storage.callMethod<JSAny?>(
          'setItem'.toJS, 'boggle.muted'.toJS, (m ? '1' : '0').toJS);
    } catch (_) {
      /* storage unavailable */
    }
  }

  /// Lazily create the pools on first play: browser autoplay policies
  /// require a user gesture before any audio, and all sounds follow one.
  static Future<void> _ensurePools() async {
    if (_ready) return;
    _ready = true;
    for (final n in _names) {
      _pools[n] = await AudioPool.create(
        source: AssetSource('sfx/$n.wav'),
        maxPlayers: n == 'tick' || n == 'tap' ? 6 : 3,
      );
    }
  }

  static Future<void> play(String name) async {
    if (muted) return;
    try {
      await _ensurePools();
      await _pools[name]?.start();
    } catch (_) {
      /* audio unavailable (headless, blocked autoplay) - never fatal */
    }
  }
}
