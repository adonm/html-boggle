/// SketchIt stroke renderer: normalized 0..1 point lists drawn with
/// perfect_freehand (tldraw's stroke algorithm) - smooth, tapered,
/// pressure-simulated lines. Pure Dart, no JS interop, so it can be
/// unit-tested.
///
/// Outline polygons are cached per stroke (recomputed only when that
/// stroke's point count changes), and the drawer's in-progress stroke is
/// painted from the live pointer buffer, so drawing never lags or
/// recomputes finished strokes.
library;

import 'package:flutter/material.dart';
import 'package:perfect_freehand/perfect_freehand.dart';

/// Paints SketchIt strokes (normalized 0..1 coordinates) with
/// perfect_freehand: smooth, tapered, pressure-simulated strokes.
class SketchPainter extends CustomPainter {
  const SketchPainter({
    required this.strokes,
    required this.rev,
    this.liveStrokeId,
    this.livePts,
    this.liveColor = 0xFF1D1D1D,
    this.liveWidth = 0.008,
  });

  final List<Map<String, dynamic>> strokes;

  /// Bumped by the logic on every stroke mutation; the list itself is
  /// mutated in place, so list identity can never detect changes.
  final int rev;

  /// The drawer's in-progress stroke: its id in [strokes], plus the
  /// pointer points buffered since the last wire flush (interleaved,
  /// normalized). Guessers pass nothing.
  final String? liveStrokeId;
  final List<double>? livePts;
  final double liveColor;
  final double liveWidth;

  static final Paint _fill = Paint()..style = PaintingStyle.fill;

  /// stroke pts list -> (point count, cached outline)
  static final Map<Object, (int, List<Offset>)> _cache = {};

  /// Interleaved [x1, y1, x2, y2, ...] normalized points -> canvas space.
  /// Public so the merge/format invariants are unit-testable.
  static List<PointVector> pointsOf(List<dynamic> pts, Size size) {
    final out = <PointVector>[];
    for (var i = 0; i + 1 < pts.length; i += 2) {
      out.add(PointVector(
        (pts[i] as num).toDouble() * size.width,
        (pts[i + 1] as num).toDouble() * size.height,
      ));
    }
    return out;
  }

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = Colors.white,
    );
    // draw committed strokes (skipping the live one; it is painted last)
    final seen = <Object>{};
    for (final s in strokes) {
      if (s['id'] == liveStrokeId && liveStrokeId != null) continue;
      seen.add(s);
      _paintStroke(canvas, size, s);
    }
    // drop cache entries for strokes that are gone
    _cache.removeWhere((key, _) => !seen.contains(key));
    // the in-progress stroke: committed points + live buffer, at full
    // pointer rate
    final live = livePts;
    if (live != null && live.isNotEmpty) {
      final base = liveStrokeId == null
          ? null
          : strokes
              .where((s) => s['id'] == liveStrokeId)
              .firstOrNull;
      final pts = <double>[
        ...(base?['pts'] as List? ?? const []).cast<double>(),
        ...live,
      ];
      _paintStroke(
        canvas,
        size,
        {'color': liveColor, 'width': liveWidth, 'pts': pts},
      );
    }
  }

  void _paintStroke(Canvas canvas, Size size, Map<String, dynamic> s) {
    final pts = s['pts'];
    if (pts is! List || pts.isEmpty) return;
    final color =
        Color((s['color'] is num ? (s['color'] as num).toInt() : 0xFF1D1D1D));
    final strokeWidth =
        ((s['width'] is num ? s['width'] as num : 0.008) * size.width)
            .clamp(1.0, 24.0);
    if (pts.length == 2) {
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
      return;
    }
    final cached = _cache[pts];
    final outline = cached != null && cached.$1 == pts.length
        ? cached.$2
        : getStroke(
            pointsOf(pts, size),
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
    if (cached == null || cached.$1 != pts.length) {
      _cache[pts] = (pts.length, outline);
    }
    if (outline.isEmpty) return;
    final path = Path()..moveTo(outline.first.dx, outline.first.dy);
    for (final p in outline.skip(1)) {
      path.lineTo(p.dx, p.dy);
    }
    path.close();
    _fill.color = color;
    canvas.drawPath(path, _fill);
  }

  @override
  bool shouldRepaint(SketchPainter oldDelegate) =>
      oldDelegate.rev != rev ||
      oldDelegate.strokes.length != strokes.length ||
      oldDelegate.liveStrokeId != liveStrokeId ||
      oldDelegate.livePts?.length != livePts?.length;
}
