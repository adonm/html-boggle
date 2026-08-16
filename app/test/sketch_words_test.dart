import 'package:boggle_app/games/sketch_words.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the sketch word list is curated, clean, and big enough', () {
    expect(sketchWords.length, greaterThan(250));
    final seen = <String>{};
    for (final w in sketchWords) {
      expect(w.length, inInclusiveRange(3, 10), reason: w);
      expect(RegExp(r'^[a-z]+$').hasMatch(w), true, reason: w);
      expect(seen.add(w), true, reason: 'duplicate word: $w');
    }
  });
}
