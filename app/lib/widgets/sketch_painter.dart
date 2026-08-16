/// SketchIt stroke renderer: normalized 0..1 point lists drawn with
/// perfect_freehand (tldraw's stroke algorithm) - smooth, tapered,
/// pressure-simulated lines. Pure Dart, no JS interop, so it can be
/// unit-tested.
library;

import 'package:flutter/material.dart';
import 'package:perfect_freehand/perfect_freehand.dart';

/// Paints SketchIt strokes (normalized 0..1 coordinates) with
/// perfect_freehand: smooth, tapered, pressure-simulated strokes.
class SketchPainter extends CustomPainter {
  const SketchPainter({required this.strokes, required this.rev});

  final List<Map<String, dynamic>> strokes;

  /// Bumped by the logic on every stroke mutation; the list itself is
  /// mutated in place, so list identity can never detect changes.
  final int rev;

  static final Paint _fill = Paint()..style = PaintingStyle.fill;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = Colors.white,
    );
    for (final s in strokes) {
      final pts = s['pts'];
      if (pts is! List || pts.isEmpty) continue;
      final n = pts.length ~/ 2;
      final color = Color(
          (s['color'] is num ? (s['color'] as num).toInt() : 0xFF1D1D1D));
      final strokeWidth =
          ((s['width'] is num ? s['width'] as num : 0.008) * size.width)
              .clamp(1.0, 24.0);
      if (n == 1) {
        // a single tap: a dot
        _fill.color = color;
        canvas.drawCircle(
          Offset(
            (pts[0] as num).toDouble() * size.width,
            (pts[1] as num).toDouble() * size.height,
          ),
          strokeWidth / 2,
          _fill,
        );
        continue;
      }
      final points = <PointVector>[
        for (var i = 0; i < n; i++)
          PointVector(
            (pts[i] as num).toDouble() * size.width,
            (pts[i + n] as num).toDouble() * size.height,
          ),
      ];
      final outline = getStroke(
        points,
        options: StrokeOptions(
          size: strokeWidth,
          thinning: 0.6,
          smoothing: 0.5,
          streamline: 0.5,
          simulatePressure: true,
          start: StrokeEndOptions.start(cap: true),
          end: StrokeEndOptions.end(cap: true),
          isComplete: true,
        ),
      );
      if (outline.isEmpty) continue;
      final path = Path()..moveTo(outline.first.dx, outline.first.dy);
      for (final p in outline.skip(1)) {
        path.lineTo(p.dx, p.dy);
      }
      path.close();
      _fill.color = color;
      canvas.drawPath(path, _fill);
    }
  }

  @override
  bool shouldRepaint(SketchPainter oldDelegate) =>
      oldDelegate.rev != rev || oldDelegate.strokes.length != strokes.length;
}
