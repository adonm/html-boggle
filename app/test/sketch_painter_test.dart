import 'package:boggle_app/widgets/sketch_painter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:perfect_freehand/perfect_freehand.dart';

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

  test('interleaved deltas merge into a sane line, not corner zigzags', () {
    // The wire format is interleaved [x1, y1, x2, y2, ...]. Deltas arrive
    // with several points per flush; merging must keep points in order.
    // (A flattened-halves delta format produced points like (x1, y2),
    // which perfect_freehand turned into giant filled blobs.)
    final pts = <double>[];
    // flush 1: one point
    pts.addAll([0.20, 0.30]);
    // flush 2: three more points along a gentle diagonal
    pts.addAll([0.22, 0.32, 0.24, 0.34, 0.26, 0.36]);
    // flush 3: two more
    pts.addAll([0.28, 0.38, 0.30, 0.40]);

    const size = Size(600, 340);
    final points = SketchPainter.pointsOf(pts, size);
    expect(points.length, 6);
    // every point lands on the diagonal: y = x + 0.10 (normalized)
    for (final p in points) {
      expect((p.dy / size.height - p.dx / size.width - 0.10).abs(),
          lessThan(1e-6));
    }
    // strictly increasing x (no zigzag back to corners)
    for (var i = 1; i < points.length; i++) {
      expect(points[i].dx, greaterThan(points[i - 1].dx));
    }

    // and the rendered outline hugs the input (no giant blobs)
    final outline = getStroke(
      points,
      options: StrokeOptions(
        size: 12,
        simulatePressure: true,
        start: StrokeEndOptions.start(cap: true),
        end: StrokeEndOptions.end(cap: true),
        isComplete: true,
      ),
    );
    var maxX = -double.infinity;
    var minY = double.infinity;
    for (final o in outline) {
      if (o.dx > maxX) maxX = o.dx;
      if (o.dy < minY) minY = o.dy;
    }
    // input spans 0.20..0.30 * 600 = 120..180; the outline stays close
    expect(maxX, lessThan(200));
    expect(minY, greaterThan(80));
  });
}
