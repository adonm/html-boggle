/// The Huddle mark: four rounded game tiles meeting at the center - a
/// huddle of games. Brand colors, crisp at any size.
library;

import 'package:flutter/material.dart';

const List<Color> huddleBrand = [
  Color(0xFFE95420), // Yaru orange
  Color(0xFF2196F3), // blue
  Color(0xFF4CAF50), // green
  Color(0xFF9C27B0), // purple
];

class HuddleMark extends StatelessWidget {
  const HuddleMark({super.key, this.size = 72});

  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _HuddleMarkPainter()),
    );
  }
}

class _HuddleMarkPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    // the 2x2 block fills 84% of the box, leaving room for the shadow
    final block = s * 0.74;
    final gap = s * 0.06;
    final half = (block - gap) / 2;
    final outer = s * 0.20;
    final inner = s * 0.05;
    final origin = Offset((s - block) / 2, (s - block) / 2);

    RRect tile(Offset at) => RRect.fromRectAndRadius(
          Rect.fromLTWH(at.dx, at.dy, half, half),
          Radius.circular(at.dx == origin.dx && at.dy == origin.dy
              ? outer // top-left: outer corner
              : at.dx != origin.dx && at.dy != origin.dy
                  ? outer // bottom-right: outer corner
                  : inner),
        );

    final centers = [
      origin,
      origin + Offset(half + gap, 0),
      origin + Offset(0, half + gap),
      origin + Offset(half + gap, half + gap),
    ];
    for (var i = 0; i < 4; i++) {
      final r = tile(centers[i]);
      canvas.drawShadow(
        Path()..addRRect(r.shift(Offset(0, s * 0.03))),
        const Color(0x55000000),
        s * 0.05,
        false,
      );
      canvas.drawRRect(
        r,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              huddleBrand[i],
              Color.lerp(huddleBrand[i], Colors.black, 0.22)!,
            ],
          ).createShader(r.outerRect),
      );
    }
  }

  @override
  bool shouldRepaint(_HuddleMarkPainter oldDelegate) => false;
}
