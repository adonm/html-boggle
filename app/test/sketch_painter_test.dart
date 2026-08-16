import 'package:boggle_app/widgets/sketch_painter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('repaints when stroke deltas mutate the list in place', () {
    // the classic bug: strokes are appended/mutated without replacing the
    // list, so identity-based shouldRepaint never fires
    final strokes = <Map<String, dynamic>>[];
    final old = SketchPainter(strokes: strokes, rev: 0);

    // a new stroke arrives (logic bumps rev)
    strokes.add({
      'id': 'a',
      'color': 1,
      'width': 0.01,
      'pts': <double>[0.1, 0.2],
    });
    var next = SketchPainter(strokes: strokes, rev: 1);
    expect(next.shouldRepaint(old), true, reason: 'new stroke must repaint');

    // a delta appends points to the SAME stroke map + list
    final before = strokes.first;
    (strokes.first['pts'] as List<double>).addAll(<double>[0.3, 0.4]);
    expect(identical(strokes.first, before), true, reason: 'mutated in place');
    next = SketchPainter(strokes: strokes, rev: 2);
    expect(next.shouldRepaint(old), true,
        reason: 'point deltas must repaint despite same list identity');

    // clearing the canvas repaints too
    strokes.clear();
    next = SketchPainter(strokes: strokes, rev: 3);
    expect(next.shouldRepaint(old), true, reason: 'clear must repaint');

    // and with no changes there is no repaint
    final same = SketchPainter(strokes: strokes, rev: 3);
    expect(same.shouldRepaint(next), false);
  });
}
