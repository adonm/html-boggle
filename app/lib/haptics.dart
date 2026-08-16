/// Richer haptics: patterned vibration on mobile, Flutter's built-in
/// feedback as the fallback (web and everywhere else).
library;

import 'package:flutter/services.dart';
import 'package:vibration/vibration.dart';

class Haptics {
  static Future<void> win() async {
    try {
      if (await Vibration.hasVibrator()) {
        await Vibration.vibrate(pattern: [0, 120, 60, 120, 60, 260]);
        return;
      }
    } catch (_) {
      /* unsupported platform */
    }
    HapticFeedback.heavyImpact();
  }

  static Future<void> fail() async {
    try {
      if (await Vibration.hasVibrator()) {
        await Vibration.vibrate(pattern: [0, 60, 40, 90]);
        return;
      }
    } catch (_) {
      /* unsupported platform */
    }
    HapticFeedback.vibrate();
  }

  static Future<void> soft() async {
    HapticFeedback.selectionClick();
  }
}
