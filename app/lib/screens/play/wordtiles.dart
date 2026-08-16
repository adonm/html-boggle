/// Word Tiles play view: rack chips + board, tap-tap to place tiles.
library;

import 'package:flutter/material.dart';

import '../../game.dart';
import '../../wordtiles.dart';


class WtPlayBody extends StatefulWidget {
  const WtPlayBody({super.key, required this.game});

  final Game game;

  @override
  State<WtPlayBody> createState() => _WtPlayBodyState();
}

class _WtPlayBodyState extends State<WtPlayBody> {
  final Map<String, String> _pending = {}; // "x:y" -> letter
  String? _selected; // selected rack letter (one instance)
  int _seenMoves = 0;

  Game get game => widget.game;

  @override
  void initState() {
    super.initState();
    _seenMoves = game.wt?.moves.length ?? 0;
    game.addListener(_onGame);
  }

  @override
  void dispose() {
    game.removeListener(_onGame);
    super.dispose();
  }

  void _onGame() {
    setState(() {
      // only a real move (someone played/passed) resets pending placements;
      // periodic hellos/state syncs must not wipe a placement in progress
      if ((game.wt?.moves.length ?? 0) != _seenMoves) {
        _seenMoves = game.wt?.moves.length ?? 0;
        _pending.clear();
        _selected = null;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final g = game;
    final board = g.wt!.board;
    final rack = g.wt!.myRack;
    final myTurn = g.meId == g.wt!.turnId;
    final isPlayer = g.wt!.seats.contains(g.meId);
    final turnName = g.players
        .where((p) => p.id == g.wt!.turnId)
        .firstOrNull
        ?.name;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
          child: Text(
            isPlayer
                ? (myTurn ? 'YOUR TURN - place tiles' : 'waiting for $turnName...')
                : 'spectating - $turnName to play',
            style: theme.textTheme.titleMedium?.copyWith(
              color: myTurn ? theme.colorScheme.primary : theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        Expanded(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560, maxHeight: 480),
              child: AspectRatio(
                aspectRatio: 1,
                child: Card(
                  clipBehavior: Clip.antiAlias,
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final sq = constraints.maxWidth / WtGame.size;
                      return Column(
                        children: [
                          for (var y = 0; y < WtGame.size; y++)
                            Row(
                              children: [
                                for (var x = 0; x < WtGame.size; x++)
                                  _wtCell(x, y, board, sq, theme),
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
            'SCORES: ${[
              for (var i = 0; i < g.wt!.seats.length; i++)
                '${g.players.where((p) => p.id == g.wt!.seats[i]).firstOrNull?.name ?? '?'} ${g.wt!.scoreOf(i)}',
            ].join(' · ')}',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall,
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 0, 8, 4),
          child: Wrap(
            alignment: WrapAlignment.center,
            children: [
              for (var i = 0; i < rack.length; i++)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
                  child: _wtChip(rack[i], i, myTurn, theme),
                ),
            ],
          ),
        ),
        if (isPlayer)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                FilledButton(
                  onPressed: (myTurn && _pending.isNotEmpty) ? _play : null,
                  child: const Text('PLAY'),
                ),
                const SizedBox(width: 8),
                OutlinedButton(
                  onPressed: (_pending.isNotEmpty)
                      ? () => setState(() {
                            _pending.clear();
                            _selected = null;
                          })
                      : null,
                  child: const Text('RECALL'),
                ),
                const SizedBox(width: 8),
                FilledButton.tonal(
                  onPressed: myTurn ? g.wt!.passTurn : null,
                  child: const Text('PASS'),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _wtCell(int x, int y, Map<String, String> board, double sq,
      ThemeData theme) {
    final key = '$x:$y';
    final pending = _pending[key];
    final letter = pending ?? board[key];
    final isCenter = x == WtGame.center && y == WtGame.center && board.isEmpty;
    final dark = (x + y).isOdd;
    return Semantics(
      label: 'word tile square $x $y',
      button: true,
      child: DragTarget<String>(
        onAcceptWithDetails: (d) {
          if (game.meId != game.wt?.turnId) return;
          if (letter != null) return; // occupied
          final i = d.data.lastIndexOf('#');
          final dragged = d.data.substring(0, i);
          setState(() {
            _pending[key] = dragged;
            _selected = null;
          });
        },
        builder: (context, _, __) => InkWell(
        onTap: () {
          if (!(game.meId == game.wt?.turnId)) return;
          if (pending != null) {
            setState(() {
              _pending.remove(key);
              _selected = null;
            });
            return;
          }
          if (letter != null) return; // occupied by a confirmed tile
          if (_selected == null) return;
          setState(() {
            // _selected is the chip key "C#0" - store just the letter
            _pending[key] = _letterOf(_selected!);
            _selected = null;
          });
        },
        child: Container(
          width: sq,
          height: sq,
          decoration: BoxDecoration(
            color: dark
                ? const Color(0xFFB8A98A)
                : const Color(0xFFE8DCC0),
            border: Border.all(
              color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.25),
              width: 0.5,
            ),
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              if (isCenter)
                Text('★',
                    style: TextStyle(
                        fontSize: sq * 0.55,
                        color: theme.colorScheme.primary)),
              if (letter != null)
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      letter,
                      style: TextStyle(
                        fontSize: sq * 0.5,
                        fontWeight: FontWeight.bold,
                        color: pending != null
                            ? theme.colorScheme.primary
                            : theme.colorScheme.onSurface,
                      ),
                    ),
                    Text(
                      '${WtGame.values[letter] ?? 0}',
                      style: TextStyle(fontSize: sq * 0.24),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
      ),
    );
  }

  Widget _wtChip(String letter, int index, bool myTurn, ThemeData theme) {
    final key = '$letter#$index';
    final chip = InkWell(
      onTap: () {
        if (!myTurn) return;
        setState(() {
          _selected = _selected == key ? null : key;
        });
      },
      child: Container(
        width: 40,
        height: 44,
        decoration: BoxDecoration(
          color: _selected == '$letter#$index'
              ? theme.colorScheme.primary
              : theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: theme.colorScheme.outline),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              letter,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: _selected == '$letter#$index'
                    ? theme.colorScheme.onPrimary
                    : theme.colorScheme.onSurface,
              ),
            ),
            Text(
              '${WtGame.values[letter] ?? 0}',
              style: TextStyle(
                fontSize: 10,
                color: _selected == '$letter#$index'
                    ? theme.colorScheme.onPrimary
                    : theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
    return Draggable<String>(
      data: key,
      dragAnchorStrategy: pointerDragAnchorStrategy,
      feedback: Material(
        color: Colors.transparent,
        child: Transform.scale(scale: 1.15, child: chip),
      ),
      childWhenDragging: Opacity(opacity: 0.4, child: chip),
      child: chip,
    );
  }

  /// The letter part of a chip key ("C#0" -> "C").
  String _letterOf(String key) => key.split('#').first;

  void _play() {
    final tiles = <List<dynamic>>[
      for (final e in _pending.entries)
        [
          int.parse(e.key.split(':')[0]),
          int.parse(e.key.split(':')[1]),
          e.value,
        ],
    ]..sort((a, b) {
        if (a[0] != b[0]) return (a[0] as int).compareTo(b[0] as int);
        return (a[1] as int).compareTo(b[1] as int);
      });
    if (game.wt?.tryPlay(tiles) == true) {
      setState(() {
        _pending.clear();
        _selected = null;
      });
    }
  }
}

