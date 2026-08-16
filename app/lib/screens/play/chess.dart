/// Chess play view: tap a piece, then a highlighted square. Moves are
/// validated by the rules engine; promotion asks for the piece.
library;

import 'package:flutter/material.dart';

import '../../chess.dart';
import '../../game.dart';
import '../../widgets/chess_piece.dart';

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
                ChessPiece(
                  piece: piece,
                  white: ChessBoard.isWhite(piece),
                  size: sq * 0.9,
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
                      child: ChessPiece(
                        piece: p.toUpperCase(),
                        white: true,
                        size: 52,
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
