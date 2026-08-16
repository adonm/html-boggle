/// Chess play view: tap a piece, then a highlighted square.
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
    final board = ChessBoard.fromMoves(g.chess!.moves);
    final isPlayer = g.meId == g.chess!.white || g.meId == g.chess!.black;
    final myTurn = g.meId == g.chess!.turnId;
    final targets = _selected == null
        ? const <int>[]
        : ChessBoard.targets(board, _selected!);
    String nameOf(String id) =>
        g.players.where((p) => p.id == id).firstOrNull?.name ?? '';
    final whiteName = nameOf(g.chess!.white).isEmpty ? 'White' : nameOf(g.chess!.white);
    final blackName = nameOf(g.chess!.black).isEmpty ? 'Black' : nameOf(g.chess!.black);
    final turnName = g.chess!.whiteTurn ? whiteName : blackName;
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
            'WHITE: $whiteName · BLACK: $blackName · capture the king to win',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall,
          ),
        ),
      ],
    );
  }

  Widget _square(int idx, List<String> board, double sq, List<int> targets,
      ThemeData theme) {
    final dark = (idx ~/ 8 + idx % 8).isOdd;
    final selected = idx == _selected;
    final target = targets.contains(idx);
    final piece = board[idx];
    return Semantics(
      label: 'chess square ${ChessBoard.sqName(idx)}',
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
          if (targets.contains(idx)) {
            final from = ChessBoard.sqName(_selected!);
            final to = ChessBoard.sqName(idx);
            setState(() => _selected = null);
            game.chess?.tryMove(from, to);
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
                Text(
                  ChessBoard.glyph(piece),
                  style: TextStyle(
                    fontSize: sq * 0.62,
                    color: ChessBoard.isWhite(piece)
                        ? Colors.white
                        : Colors.black,
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
}

