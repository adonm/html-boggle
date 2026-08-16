/// Chess play view: tap a piece, then a highlighted square. Standard rules
/// use the engine's legal moves (castling, en passant, promotion dialog);
/// party rules highlight capture-chess targets.
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
            logic.rules == 'standard'
                ? 'WHITE: $whiteName · BLACK: $blackName · checkmate wins'
                : 'WHITE: $whiteName · BLACK: $blackName · capture the king to win',
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
                  size: Size.square(sq * 0.94),
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

/// License-clean stylized pieces: layered geometric silhouettes instead of
/// the (GPL) cburnett artwork or system emoji glyphs.
class ChessPiecePainter extends CustomPainter {
  const ChessPiecePainter({required this.piece, required this.white});

  /// 'P','N','B','R','Q','K' (case irrelevant).
  final String piece;
  final bool white;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    final fill = white ? const Color(0xFFF8F6F0) : const Color(0xFF22201C);
    final outline = white ? const Color(0xFF22201C) : const Color(0xFFF8F6F0);
    final shadow = white ? const Color(0x33000000) : const Color(0x55000000);
    final c = Offset(size.width / 2, size.height / 2);
    final paintFill = Paint()..color = fill;
    final paintOutline = Paint()
      ..color = outline
      ..style = PaintingStyle.stroke
      ..strokeWidth = s * 0.045
      ..strokeJoin = StrokeJoin.round;

    Path path() => Path()..fillType = PathFillType.evenOdd;

    switch (piece.toUpperCase()) {
      case 'P':
        canvas.drawCircle(
            c.translate(0, -s * 0.32), s * 0.26, paintFill);
        canvas.drawCircle(
            c.translate(0, -s * 0.32), s * 0.26, paintOutline);
        canvas.drawPath(
          path()
            ..moveTo(c.dx - s * 0.3, c.dy + s * 0.42)
            ..quadraticBezierTo(c.dx, c.dy + s * 0.1, c.dx + s * 0.3, c.dy + s * 0.42)
            ..close(),
          paintFill,
        );
        canvas.drawPath(
          path()
            ..moveTo(c.dx - s * 0.3, c.dy + s * 0.42)
            ..quadraticBezierTo(c.dx, c.dy + s * 0.1, c.dx + s * 0.3, c.dy + s * 0.42)
            ..close(),
          paintOutline,
        );
      case 'N':
        final p = path()
          ..moveTo(c.dx - s * 0.28, c.dy + s * 0.38)
          ..lineTo(c.dx - s * 0.28, c.dy - s * 0.05)
          ..quadraticBezierTo(c.dx - s * 0.28, c.dy - s * 0.3, c.dx, c.dy - s * 0.32)
          ..quadraticBezierTo(c.dx + s * 0.3, c.dy - s * 0.25, c.dx + s * 0.34, c.dy + s * 0.05)
          ..quadraticBezierTo(c.dx + s * 0.12, c.dy + s * 0.18, c.dx + s * 0.08, c.dy + s * 0.34)
          ..close();
        canvas.drawPath(p, paintFill);
        canvas.drawPath(p, paintOutline);
        canvas.drawPath(
          path()
            ..moveTo(c.dx - s * 0.16, c.dy - s * 0.28)
            ..lineTo(c.dx - s * 0.22, c.dy - s * 0.44)
            ..lineTo(c.dx + s * 0.02, c.dy - s * 0.34)
            ..close(),
          paintFill,
        );
      case 'B':
        final p = path()
          ..moveTo(c.dx, c.dy - s * 0.44)
          ..quadraticBezierTo(c.dx + s * 0.3, c.dy + s * 0.2, c.dx, c.dy + s * 0.36)
          ..lineTo(c.dx - s * 0.06, c.dy + s * 0.42)
          ..lineTo(c.dx + s * 0.06, c.dy + s * 0.42)
          ..lineTo(c.dx, c.dy + s * 0.36)
          ..quadraticBezierTo(c.dx - s * 0.3, c.dy + s * 0.2, c.dx, c.dy - s * 0.44)
          ..close();
        canvas.drawPath(p, paintFill);
        canvas.drawPath(p, paintOutline);
        canvas.drawCircle(c.translate(0, -s * 0.46), s * 0.07, paintFill);
      case 'R':
        final p = path()
          ..moveTo(c.dx - s * 0.3, c.dy - s * 0.42)
          ..lineTo(c.dx - s * 0.3, c.dy - s * 0.2)
          ..lineTo(c.dx - s * 0.14, c.dy - s * 0.2)
          ..lineTo(c.dx - s * 0.14, c.dy - s * 0.42)
          ..lineTo(c.dx, c.dy - s * 0.42)
          ..lineTo(c.dx, c.dy - s * 0.2)
          ..lineTo(c.dx + s * 0.14, c.dy - s * 0.2)
          ..lineTo(c.dx + s * 0.14, c.dy - s * 0.42)
          ..lineTo(c.dx + s * 0.3, c.dy - s * 0.42)
          ..lineTo(c.dx + s * 0.3, c.dy + s * 0.42)
          ..lineTo(c.dx - s * 0.3, c.dy + s * 0.42)
          ..close();
        canvas.drawPath(p, paintFill);
        canvas.drawPath(p, paintOutline);
      case 'Q':
        final p = path()
          ..moveTo(c.dx - s * 0.24, c.dy - s * 0.42)
          ..lineTo(c.dx - s * 0.4, c.dy + s * 0.4)
          ..quadraticBezierTo(c.dx, c.dy + s * 0.18, c.dx + s * 0.4, c.dy + s * 0.4)
          ..lineTo(c.dx + s * 0.24, c.dy - s * 0.42)
          ..lineTo(c.dx + s * 0.08, c.dy - s * 0.16)
          ..lineTo(c.dx, c.dy - s * 0.42)
          ..lineTo(c.dx - s * 0.08, c.dy - s * 0.16)
          ..close();
        canvas.drawPath(p, paintFill);
        canvas.drawPath(p, paintOutline);
        canvas.drawCircle(c.translate(0, -s * 0.46), s * 0.07, paintFill);
      case 'K':
        final p = path()
          ..moveTo(c.dx - s * 0.26, c.dy - s * 0.38)
          ..lineTo(c.dx - s * 0.4, c.dy + s * 0.42)
          ..quadraticBezierTo(c.dx, c.dy + s * 0.16, c.dx + s * 0.4, c.dy + s * 0.42)
          ..lineTo(c.dx + s * 0.26, c.dy - s * 0.38)
          ..lineTo(c.dx + s * 0.1, c.dy - s * 0.12)
          ..lineTo(c.dx + s * 0.1, c.dy - s * 0.38)
          ..lineTo(c.dx, c.dy - s * 0.38)
          ..lineTo(c.dx - s * 0.1, c.dy - s * 0.38)
          ..lineTo(c.dx - s * 0.1, c.dy - s * 0.12)
          ..close();
        canvas.drawPath(p, paintFill);
        canvas.drawPath(p, paintOutline);
        canvas.drawRect(
          Rect.fromCenter(
              center: c.translate(0, -s * 0.44), width: s * 0.09, height: s * 0.26),
          paintFill,
        );
        canvas.drawRect(
          Rect.fromCenter(
              center: c.translate(0, -s * 0.36), width: s * 0.3, height: s * 0.09),
          paintFill,
        );
    }
    // ground shadow ellipse for depth
    canvas.drawOval(
      Rect.fromCenter(
          center: c.translate(0, s * 0.44), width: s * 0.56, height: s * 0.12),
      Paint()..color = shadow,
    );
  }

  @override
  bool shouldRepaint(ChessPiecePainter oldDelegate) =>
      oldDelegate.piece != piece || oldDelegate.white != white;
}
