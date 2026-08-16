/// License-clean Staunton-style chess pieces: layered geometric silhouettes
/// with gradient shading, drawn as paths so they stay crisp at any size.
library;

import 'package:flutter/material.dart';

/// License-clean Staunton-style pieces: layered geometric silhouettes with
/// gradient shading, drawn with paths so they stay crisp at any size.
class ChessPiecePainter extends CustomPainter {
  const ChessPiecePainter({required this.piece, required this.white});

  /// 'P','N','B','R','Q','K' (case irrelevant).
  final String piece;
  final bool white;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    final c = Offset(size.width / 2, size.height / 2);
    final bottom = c.dy + s * 0.46;
    final fill = white
        ? const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFFFFFFFF), Color(0xFFE4E0D6)],
          )
        : const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF57534E), Color(0xFF1C1917)],
          );
    final outlineColor = white ? const Color(0xFF3A352F) : const Color(0xFF0A0908);
    final stroke = s * 0.035;

    // ground shadow, drawn first so pieces sit on top of it
    canvas.drawOval(
      Rect.fromCenter(
          center: Offset(c.dx, bottom + s * 0.02),
          width: s * 0.6,
          height: s * 0.1),
      Paint()..color = const Color(0x40000000),
    );

    void draw(Path p) {
      canvas.drawShadow(p, const Color(0x66000000), s * 0.05, false);
      canvas.drawPath(p, Paint()..shader = fill.createShader(Offset.zero & size));
      canvas.drawPath(
        p,
        Paint()
          ..color = outlineColor
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke
          ..strokeJoin = StrokeJoin.round
          ..strokeCap = StrokeCap.round,
      );
    }

    final base = Path()
      ..moveTo(c.dx - s * 0.27, bottom)
      ..lineTo(c.dx - s * 0.33, bottom - s * 0.1)
      ..lineTo(c.dx + s * 0.33, bottom - s * 0.1)
      ..lineTo(c.dx + s * 0.27, bottom)
      ..close();

    Path p = Path();
    switch (piece.toUpperCase()) {
      case 'P': // sphere head + collar + tapered body
        p
          ..moveTo(c.dx - s * 0.18, c.dy - s * 0.02)
          ..quadraticBezierTo(c.dx - s * 0.3, c.dy + s * 0.16,
              c.dx - s * 0.26, c.dy + s * 0.4)
          ..lineTo(c.dx + s * 0.26, c.dy + s * 0.4)
          ..quadraticBezierTo(
              c.dx + s * 0.3, c.dy + s * 0.16, c.dx + s * 0.18, c.dy - s * 0.02)
          ..quadraticBezierTo(
              c.dx, c.dy - s * 0.1, c.dx - s * 0.18, c.dy - s * 0.02)
          ..close();
        draw(p);
        canvas.drawCircle(
            c.translate(0, -s * 0.22), s * 0.17, Paint()..shader = fill.createShader(Offset.zero & size));
        canvas.drawCircle(
            c.translate(0, -s * 0.22),
            s * 0.17,
            Paint()
              ..color = outlineColor
              ..style = PaintingStyle.stroke
              ..strokeWidth = stroke);
        draw(base);
      case 'N': // horse head in profile
        p
          ..moveTo(c.dx + s * 0.26, c.dy + s * 0.38)
          ..quadraticBezierTo(c.dx + s * 0.3, c.dy + s * 0.1, c.dx + s * 0.16, c.dy - s * 0.28)
          ..quadraticBezierTo(c.dx + s * 0.02, c.dy - s * 0.4, c.dx - s * 0.14, c.dy - s * 0.42)
          ..quadraticBezierTo(c.dx - s * 0.3, c.dy - s * 0.38, c.dx - s * 0.3, c.dy - s * 0.14)
          ..quadraticBezierTo(c.dx - s * 0.26, c.dy - s * 0.02, c.dx - s * 0.16, c.dy + s * 0.02)
          ..lineTo(c.dx - s * 0.1, c.dy + s * 0.14)
          ..quadraticBezierTo(c.dx - s * 0.3, c.dy + s * 0.3, c.dx - s * 0.24, c.dy + s * 0.42)
          ..lineTo(c.dx + s * 0.26, c.dy + s * 0.42)
          ..close();
        draw(p);
        // eye dot
        canvas.drawCircle(
          c.translate(s * 0.02, -s * 0.24),
          s * 0.035,
          Paint()..color = outlineColor,
        );
        draw(base);
      case 'B': // mitre with slit + ball
        p
          ..moveTo(c.dx, c.dy - s * 0.42)
          ..quadraticBezierTo(c.dx + s * 0.24, c.dy + s * 0.2, c.dx + s * 0.02, c.dy + s * 0.4)
          ..lineTo(c.dx - s * 0.02, c.dy + s * 0.4)
          ..quadraticBezierTo(c.dx - s * 0.24, c.dy + s * 0.2, c.dx, c.dy - s * 0.42)
          ..close();
        draw(p);
        // the slit
        canvas.drawLine(
          c.translate(0, -s * 0.3),
          c.translate(0, s * 0.1),
          Paint()
            ..color = outlineColor
            ..strokeWidth = stroke * 0.8
            ..strokeCap = StrokeCap.round,
        );
        canvas.drawCircle(c.translate(0, -s * 0.46), s * 0.06,
            Paint()..color = outlineColor);
        draw(base);
      case 'R': // battlements + tapered tower
        p
          ..moveTo(c.dx - s * 0.24, c.dy - s * 0.4)
          ..lineTo(c.dx - s * 0.24, c.dy - s * 0.12)
          ..lineTo(c.dx - s * 0.12, c.dy - s * 0.12)
          ..lineTo(c.dx - s * 0.12, c.dy - s * 0.4)
          ..lineTo(c.dx - s * 0.04, c.dy - s * 0.4)
          ..lineTo(c.dx - s * 0.04, c.dy - s * 0.12)
          ..lineTo(c.dx + s * 0.04, c.dy - s * 0.12)
          ..lineTo(c.dx + s * 0.04, c.dy - s * 0.4)
          ..lineTo(c.dx + s * 0.12, c.dy - s * 0.4)
          ..lineTo(c.dx + s * 0.12, c.dy - s * 0.12)
          ..lineTo(c.dx + s * 0.24, c.dy - s * 0.12)
          ..lineTo(c.dx + s * 0.24, c.dy - s * 0.4)
          ..lineTo(c.dx + s * 0.24, c.dy + s * 0.4)
          ..lineTo(c.dx - s * 0.24, c.dy + s * 0.4)
          ..close();
        draw(p);
        draw(base);
      case 'Q': // coronet with spheres
        p
          ..moveTo(c.dx - s * 0.2, c.dy - s * 0.3)
          ..quadraticBezierTo(c.dx - s * 0.28, c.dy + s * 0.16,
              c.dx - s * 0.22, c.dy + s * 0.4)
          ..lineTo(c.dx + s * 0.22, c.dy + s * 0.4)
          ..quadraticBezierTo(c.dx + s * 0.28, c.dy + s * 0.16,
              c.dx + s * 0.2, c.dy - s * 0.3)
          ..close();
        draw(p);
        // coronet band + spheres
        canvas.drawRect(
          Rect.fromCenter(
              center: c.translate(0, -s * 0.32),
              width: s * 0.44,
              height: s * 0.09),
          Paint()..shader = fill.createShader(Offset.zero & size),
        );
        canvas.drawRect(
          Rect.fromCenter(
              center: c.translate(0, -s * 0.32),
              width: s * 0.44,
              height: s * 0.09),
          Paint()
            ..color = outlineColor
            ..style = PaintingStyle.stroke
            ..strokeWidth = stroke * 0.8,
        );
        for (final dx in [-0.18, -0.06, 0.06, 0.18]) {
          canvas.drawCircle(
              c.translate(s * dx, -s * 0.42), s * 0.055, Paint()..color = outlineColor);
        }
        draw(base);
      case 'K': // cross + crown
        p
          ..moveTo(c.dx - s * 0.19, c.dy - s * 0.26)
          ..quadraticBezierTo(c.dx - s * 0.27, c.dy + s * 0.14,
              c.dx - s * 0.21, c.dy + s * 0.4)
          ..lineTo(c.dx + s * 0.21, c.dy + s * 0.4)
          ..quadraticBezierTo(c.dx + s * 0.27, c.dy + s * 0.14,
              c.dx + s * 0.19, c.dy - s * 0.26)
          ..close();
        draw(p);
        // cross
        canvas.drawRect(
          Rect.fromCenter(
              center: c.translate(0, -s * 0.42),
              width: s * 0.075,
              height: s * 0.3),
          Paint()..color = outlineColor,
        );
        canvas.drawRect(
          Rect.fromCenter(
              center: c.translate(0, -s * 0.36),
              width: s * 0.24,
              height: s * 0.075),
          Paint()..color = outlineColor,
        );
        draw(base);
    }
  }

  @override
  bool shouldRepaint(ChessPiecePainter oldDelegate) =>
      oldDelegate.piece != piece || oldDelegate.white != white;
}
