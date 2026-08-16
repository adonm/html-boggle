/// Chess play view: tap a piece, then a highlighted square. Moves are
/// validated by the rules engine; promotion asks for the piece.
library;

import 'package:flutter/material.dart';

import '../../chess.dart';
import '../../game.dart';

class ChessPlayBody extends StatefulWidget {
  const ChessPlayBody({super.key, required this.game});

  final Game game;

  @override
  State<ChessPlayBody> createState() => _ChessPlayBodyState();
}

class _ChessPlayBodyState extends State<ChessPlayBody> {
  int? _selected;

  Game get game => widget.game;

  @override
  void initState() {
    super.initState();
    game.addListener(_onGame);
  }

  @override
  void dispose() {
    game.removeListener(_onGame);
    super.dispose();
  }

  void _onGame() => setState(() {});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final g = game;
    final logic = g.chess!;
    final board = logic.displayBoard;
    final isPlayer = g.meId == logic.white || g.meId == logic.black;
    final myTurn = g.meId == logic.turnId;
    final targets = _selected == null
        ? const <String>{}
        : logic.legalTargetsFrom(ChessBoard.sqName(_selected!));
    String nameOf(String id) =>
        g.players.where((p) => p.id == id).firstOrNull?.name ?? '';
    final whiteName = nameOf(logic.white).isEmpty ? 'White' : nameOf(logic.white);
    final blackName = nameOf(logic.black).isEmpty ? 'Black' : nameOf(logic.black);
    final turnName = logic.whiteTurn ? whiteName : blackName;
    final check = logic.isCheck && logic.winner.isEmpty;
    final status = isPlayer
        ? (myTurn ? (check ? 'CHECK - YOUR MOVE' : 'YOUR MOVE') : 'waiting for $turnName...')
        : 'spectating - $turnName to move';
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(8),
          child: Text(
            status,
            style: theme.textTheme.titleMedium?.copyWith(
              color: check
                  ? theme.colorScheme.error
                  : myTurn
                      ? theme.colorScheme.primary
                      : theme.colorScheme.onSurfaceVariant,
              fontWeight: check ? FontWeight.bold : null,
            ),
          ),
        ),
        Expanded(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: AspectRatio(
                aspectRatio: 1,
                child: Card(
                  clipBehavior: Clip.antiAlias,
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final sq = constraints.maxWidth / 8;
                      return Column(
                        children: [
                          for (var r = 0; r < 8; r++)
                            Row(
                              children: [
                                for (var c = 0; c < 8; c++)
                                  _square(
                                    r * 8 + c,
                                    board,
                                    sq,
                                    targets,
                                    theme,
                                  ),
                              ],
                            ),
                        ],
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(8),
          child: Text(
            'WHITE: $whiteName · BLACK: $blackName · checkmate wins',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall,
          ),
        ),
      ],
    );
  }

  Widget _square(int idx, List<String> board, double sq, Set<String> targets,
      ThemeData theme) {
    final dark = (idx ~/ 8 + idx % 8).isOdd;
    final selected = idx == _selected;
    final name = ChessBoard.sqName(idx);
    final target = targets.contains(name);
    final piece = board[idx];
    return Semantics(
      label: 'chess square $name',
      button: true,
      child: InkWell(
        onTap: () {
          if (game.meId != game.chess?.turnId) return;
          if (_selected == null) {
            if (piece != '.' &&
                ChessBoard.isWhite(piece) == game.chess?.whiteTurn) {
              setState(() => _selected = idx);
            }
            return;
          }
          if (target) {
            final from = ChessBoard.sqName(_selected!);
            setState(() => _selected = null);
            _move(from, name);
            return;
          }
          if (piece != '.' &&
              ChessBoard.isWhite(piece) == game.chess?.whiteTurn &&
              idx != _selected) {
            setState(() => _selected = idx);
            return;
          }
          setState(() => _selected = null);
        },
        child: Container(
          width: sq,
          height: sq,
          decoration: BoxDecoration(
            color: selected
                ? theme.colorScheme.primary.withValues(alpha: 0.5)
                : dark
                    ? const Color(0xFFB58863)
                    : const Color(0xFFF0D9B5),
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              if (piece != '.')
                CustomPaint(
                  size: Size.square(sq * 0.92),
                  painter: ChessPiecePainter(
                    piece: piece,
                    white: ChessBoard.isWhite(piece),
                  ),
                ),
              if (target)
                Container(
                  width: sq * 0.28,
                  height: sq * 0.28,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary.withValues(alpha: 0.6),
                    shape: BoxShape.circle,
                  ),
                ),
              if (target && piece != '.')
                Container(
                  width: sq,
                  height: sq,
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: theme.colorScheme.primary,
                      width: 3,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// Move, asking for the promotion piece when the engine requires one.
  void _move(String from, String to) {
    final promo = game.chess?.promotionFor(from, to);
    if (promo == null) {
      game.chess?.tryMove(from, to);
      return;
    }
    showDialog<void>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Promote to'),
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              for (final p in const ['q', 'r', 'b', 'n'])
                InkWell(
                  onTap: () {
                    Navigator.pop(context);
                    game.chess?.tryMove(from, to, promo: p);
                  },
                  child: Padding(
                    padding: const EdgeInsets.all(10),
                    child: SizedBox(
                      width: 52,
                      height: 52,
                      child: CustomPaint(
                        painter: ChessPiecePainter(
                          piece: p.toUpperCase(),
                          white: true,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

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
