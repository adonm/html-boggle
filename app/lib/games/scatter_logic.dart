/// Scattergories: a served letter, dictionary-word submissions, duplicate
/// cancellation at the reveal. Scoring is local + deterministic (unique
/// words count), so every client agrees without arbitration.
library;

import 'package:flutter/services.dart';

import 'game_logic.dart';
import 'turn_game.dart';

class ScatterLogic extends GameLogic {
  ScatterLogic(super.host);

  @override
  String get wireName => 'scattergories';

  static const String letters = 'ABCDEFGHIJKLMNOPRSTUVWY'; // no Q, X, Z

  String letter = '';
  final Map<String, List<String>> submissions = {};

  @override
  String get startToast =>
      'Round ${host.round} - words starting with $letter!';

  @override
  void populateStart(Map<String, dynamic> msg) {
    letter = letters[host.rng.nextInt(letters.length)];
    submissions.clear();
    msg['letter'] = letter;
  }

  @override
  void applyStart(Map<String, dynamic> m) {
    letter = (m['letter'] as String?) ?? '';
    submissions.clear();
  }

  @override
  void onMessage(String type, Map<String, dynamic> m, String from) {
    if (type != 'sgSubmit') return;
    if (host.phase != Phase.play) return;
    final w = ((m['word'] as String?) ?? '').trim().toLowerCase();
    if (w.length < 3 || !w.startsWith(letter.toLowerCase())) return;
    if (!host.finder.hasWord(w)) return;
    final list = submissions.putIfAbsent(from, () => []);
    if (!list.contains(w)) list.add(w);
  }

  void submit(String raw) {
    final w = raw.trim().toLowerCase();
    if (host.phase != Phase.play) return;
    if (w.length < 3) {
      host.pulseWordAttempt();
      HapticFeedback.selectionClick();
      host.showToast('Words need at least 3 letters');
      host.notifyListeners();
      return;
    }
    if (!w.startsWith(letter.toLowerCase())) {
      host.pulseWordAttempt();
      HapticFeedback.selectionClick();
      host.showToast('Must start with "$letter"');
      host.notifyListeners();
      return;
    }
    if (!host.finder.hasWord(w)) {
      host.pulseWordAttempt();
      HapticFeedback.selectionClick();
      host.showToast('"$w" is not in the dictionary');
      host.notifyListeners();
      return;
    }
    if ((submissions[host.meId] ?? const <String>[]).contains(w)) {
      host.pulseWordAttempt();
      HapticFeedback.selectionClick();
      host.showToast('You already submitted "$w"');
      host.notifyListeners();
      return;
    }
    submissions.putIfAbsent(host.meId, () => []).add(w);
    host.send({'t': 'sgSubmit', 'node': host.meId, 'name': host.myName, 'word': w});
    HapticFeedback.selectionClick();
    host.notifyListeners();
  }

  /// Did more than one player submit [w]?
  bool isDupe(String w) =>
      submissions.entries.where((e) => e.value.contains(w)).length > 1;

  /// Unique words only.
  int scoreOf(String id) {
    var score = 0;
    for (final w in submissions[id] ?? const <String>[]) {
      if (!isDupe(w)) score++;
    }
    return score;
  }

  List<String> get allWords =>
      (submissions.values.expand((l) => l).toSet().toList())..sort();

  @override
  Map<String, dynamic> stateJson() => {
        'letter': letter,
        'sgWords': {for (final e in submissions.entries) e.key: e.value},
      };

  @override
  void adoptState(Map<String, dynamic> m) {
    letter = adoptNonEmpty(letter, m['letter']);
    final sg = m['sgWords'];
    if (sg is Map) {
      submissions.clear();
      for (final e in sg.entries) {
        if (e.key is String && e.value is List) {
          submissions[e.key as String] = [
            for (final w in (e.value as List)) if (w is String) w,
          ];
        }
      }
    }
  }

  @override
  Map<String, dynamic> debugJson() => {
        'letter': letter,
        'sgCount': submissions[host.meId]?.length ?? 0,
        'sgScore': scoreOf(host.meId),
        'sgScores': {for (final id in submissions.keys) id: scoreOf(id)},
        'sgAll': allWords.join(','),
        'sgDupes': allWords.where(isDupe).join(','),
      };

  @override
  void reset() {
    letter = '';
    submissions.clear();
  }
}
