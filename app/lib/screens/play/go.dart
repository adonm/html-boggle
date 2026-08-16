/// Go (9x9) play view: tap an intersection to place a stone.
library;

import 'package:flutter/material.dart';

import '../../game.dart';
import '../../go.dart';


class GoPlayBody extends StatefulWidget {
  const GoPlayBody({super.key, required this.game});

  final Game game;

  @override
  State<GoPlayBody> createState() => _GoPlayBodyState();
}

class _GoPlayBodyState extends State<GoPlayBody> {
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

  Widget _cell(int x, int y, double sq, bool myTurn) {
    final coord = GoGame.coord(y * 9 + x);
    return Semantics(
      label: 'go cell $coord',
      button: true,
      child: SizedBox(
        width: sq,
        height: sq,
        child: InkWell(
          onTap: myTurn ? () => game.go?.tryMove(coord) : null,
          child: const SizedBox.expand(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final g = game;
    final r = GoGame.replay(g.go!.moves);
    final myTurn = g.meId == g.go!.turnId;
    final isPlayer = g.meId == g.go!.black || g.meId == g.go!.white;
    final lastIdx = g.go!.moves.isNotEmpty &&
            g.go!.moves.last != 'pass' &&
            g.go!.moves.last != 'resign'
        ? GoGame.sq(g.go!.moves.last)
        : -1;
    String nameOf(String id) =>
        g.players.where((p) => p.id == id).firstOrNull?.name ?? id;
    final turnName = g.go!.blackTurn
        ? (nameOf(g.go!.black).isEmpty ? 'Black' : nameOf(g.go!.black))
        : (nameOf(g.go!.white).isEmpty ? 'White' : nameOf(g.go!.white));
    final blackCount = r.board.where((c) => c == 'B').length;
    final whiteCount = r.board.where((c) => c == 'W').length;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(8),
          child: Text(
            isPlayer
                ? (myTurn ? 'YOUR MOVE' : 'waiting for $turnName...')
                : 'spectating - $turnName to move',
            style: theme.textTheme.titleMedium?.copyWith(
              color: myTurn ? theme.colorScheme.primary : theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        Expanded(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: AspectRatio(
                aspectRatio: 1,
                child: Card(
                  clipBehavior: Clip.antiAlias,
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final size = Size(
                        constraints.maxWidth,
                        constraints.maxHeight,
                      );
                      final sq = size.width / 9;
                      return Stack(
                        children: [
                          Positioned.fill(
                            child: CustomPaint(
                              size: size,
                              painter: GoPainter(
                                board: r.board,
                                lastIdx: lastIdx,
                                theme: theme,
                              ),
                            ),
                          ),
                          Column(
                            children: [
                              for (var y = 0; y < 9; y++)
                                Row(
                                  children: [
                                    for (var x = 0; x < 9; x++)
                                      _cell(x, y, sq, myTurn),
                                  ],
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
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                'BLACK $blackCount · WHITE $whiteCount',
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(width: 16),
              if (isPlayer) ...[
                FilledButton.tonal(
                  onPressed: myTurn ? g.go!.passTurn : null,
                  child: const Text('PASS'),
                ),
                const SizedBox(width: 8),
                OutlinedButton(
                  onPressed: g.go!.resign,
                  child: const Text('RESIGN'),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// Paints the 9x9 grid, star points, stones, and the last-move marker.
class GoPainter extends CustomPainter {
  const GoPainter({
    required this.board,
    required this.lastIdx,
    required this.theme,
  });

  final List<String> board;
  final int lastIdx;
  final ThemeData theme;

  @override
  void paint(Canvas canvas, Size size) {
    final bg = Paint()..color = theme.colorScheme.surfaceContainerHighest;
    canvas.drawRect(Offset.zero & size, bg);
    final step = size.width / 9;
    final line = Paint()
      ..color = theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.7)
      ..strokeWidth = 1.2;
    for (var i = 0; i < 9; i++) {
      final p = step * (i + 0.5);
      canvas.drawLine(Offset(step / 2, p), Offset(size.width - step / 2, p), line);
      canvas.drawLine(Offset(p, step / 2), Offset(p, size.height - step / 2), line);
    }
    // star points (hoshi)
    final star = Paint()..color = theme.colorScheme.onSurfaceVariant;
    for (final h in const [2, 6]) {
      for (final v in const [2, 6]) {
        canvas.drawCircle(
          Offset(step * (h + 0.5), step * (v + 0.5)),
          step * 0.09,
          star,
        );
      }
    }
    canvas.drawCircle(Offset(step * 4.5, step * 4.5), step * 0.09, star);

    for (var i = 0; i < 81; i++) {
      if (board[i] == '.') continue;
      final x = step * (i % 9 + 0.5);
      final y = step * (i ~/ 9 + 0.5);
      final center = Offset(x, y);
      final stone = Paint()
        ..color = board[i] == 'B' ? const Color(0xFF2B2B2B) : const Color(0xFFF5F5F5)
        ..style = PaintingStyle.fill;
      canvas.drawCircle(center, step * 0.42, stone);
      if (board[i] == 'W') {
        canvas.drawCircle(
          center,
          step * 0.42,
          Paint()
            ..color = theme.colorScheme.onSurfaceVariant
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1,
        );
      }
      if (i == lastIdx) {
        canvas.drawCircle(
          center,
          step * 0.12,
          Paint()
            ..color = board[i] == 'B' ? Colors.white : Colors.black,
        );
      }
    }
  }

  @override
  bool shouldRepaint(GoPainter oldDelegate) =>
      oldDelegate.board.toString() != board.toString() ||
      oldDelegate.lastIdx != lastIdx;
}

