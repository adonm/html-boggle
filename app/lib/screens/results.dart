/// Round results: per-game banners plus the ranking card.
library;

import 'package:confetti/confetti.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../game.dart';
import '../go.dart';
import '../theme.dart';
import 'shared.dart';


class ScatterResultsBody extends StatelessWidget {
  const ScatterResultsBody({super.key, required this.game});

  final Game game;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final g = game;
    final ranked = [...g.players]
      ..sort((a, b) => g.scatter!.scoreOf(b.id).compareTo(g.scatter!.scoreOf(a.id)));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'LETTER ${g.scatter!.letter} · ROUND ${g.round} OVER',
          textAlign: TextAlign.center,
          style: theme.textTheme.headlineMedium?.copyWith(
            color: theme.colorScheme.primary,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final p in ranked)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            '${p.name}${p.isMe ? ' (you)' : ''}',
                            style: p.isMe
                                ? const TextStyle(
                                    color: BoggleColors.youGreen,
                                    fontWeight: FontWeight.bold,
                                  )
                                : null,
                          ),
                        ),
                        Text('${g.scatter!.scoreOf(p.id)} pts'),
                      ],
                    ),
                  ),
                const Divider(),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final w in g.scatter!.allWords)
                      Chip(
                        visualDensity: VisualDensity.compact,
                        label: Text(
                          g.scatter!.isDupe(w) ? '${w.toUpperCase()} ✗' : '${w.toUpperCase()} ✓',
                          style: TextStyle(
                            decoration: g.scatter!.isDupe(w) ? TextDecoration.lineThrough : null,
                            color: g.scatter!.isDupe(w)
                                ? theme.colorScheme.error
                                : BoggleColors.youGreen,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  '✓ counts, ✗ duplicates cancel',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------- results

class ResultsScreen extends StatefulWidget {
  const ResultsScreen({super.key, required this.game});

  final Game game;

  @override
  State<ResultsScreen> createState() => _ResultsScreenState();
}

class _ResultsScreenState extends State<ResultsScreen> {
  final ConfettiController _confetti = ConfettiController(duration: 1600.ms);

  Game get game => widget.game;

  @override
  void initState() {
    super.initState();
    _confetti.play();
  }

  @override
  void dispose() {
    _confetti.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final g = game;
    final ranked = [...g.players]
      ..sort((a, b) => b.score.compareTo(a.score));
    return Stack(
      children: [
        Positioned.fill(
          child: Center(
            child: SingleChildScrollView(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (g.mode == GameMode.scattergories)
                  ScatterResultsBody(game: g)
                else if (g.mode == GameMode.sketchit) ...[
                  SketchResultsBanner(game: g),
                  const SizedBox(height: 12),
                  _ResultsScoreCard(ranked: ranked),
                ] else if (g.mode == GameMode.chess) ...[
                  ChessResultsBanner(game: g),
                  const SizedBox(height: 12),
                  _ResultsScoreCard(ranked: ranked),
                ] else if (g.mode == GameMode.go) ...[
                  GoResultsBanner(game: g),
                  const SizedBox(height: 12),
                  _ResultsScoreCard(ranked: ranked),
                ] else if (g.mode == GameMode.wordtiles) ...[
                  WtResultsBanner(game: g),
                  const SizedBox(height: 12),
                  _ResultsScoreCard(ranked: ranked),
                ] else ...[
                  Text(
                    'ROUND ${g.round} OVER',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.headlineMedium?.copyWith(
                      color: theme.colorScheme.primary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 18),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          for (var i = 0; i < ranked.length; i++)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 6),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (i < 3)
                                  Padding(
                                    padding: const EdgeInsets.only(right: 8, top: 2),
                                    child: Icon(
                                      Icons.emoji_events,
                                      size: 22,
                                      color: const [
                                        BoggleColors.medalGold,
                                        BoggleColors.medalSilver,
                                        BoggleColors.medalBronze,
                                      ][i],
                                    ),
                                  )
                                else
                                  SizedBox(
                                    width: 32,
                                    child: Text(
                                      '${i + 1}.',
                                      style: theme.textTheme.titleMedium,
                                    ),
                                  ),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        '${ranked[i].name}${ranked[i].isMe ? ' (you)' : ''}',
                                        style: ranked[i].isMe
                                            ? const TextStyle(
                                                color: BoggleColors.youGreen,
                                                fontWeight: FontWeight.bold,
                                              )
                                            : theme.textTheme.titleMedium,
                                      ),
                                      if (ranked[i].words.isNotEmpty)
                                        Text(
                                          ranked[i].words.map((w) => w.toUpperCase()).join(', '),
                                          style: theme.textTheme.bodySmall,
                                        ),
                                    ],
                                  ),
                                ),
                                Text(
                                  '${ranked[i].score} pts',
                                  style: theme.textTheme.titleMedium,
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                ],
                const SizedBox(height: 18),
                ReadyStartControls(game: g, startLabel: 'NEXT ROUND'),
                const SizedBox(height: 6),
                TextButton.icon(
                  onPressed: g.leaveRoom,
                  icon: const Icon(Icons.logout, size: 18),
                  label: const Text('LEAVE ROOM'),
                ),
              ],
            ),
          ),
        ),
      ),
        ),
      ),
      Align(
        alignment: Alignment.topCenter,
        child: ConfettiWidget(
          confettiController: _confetti,
          blastDirectionality: BlastDirectionality.explosive,
          emissionFrequency: 0.05,
            numberOfParticles: 45,
            gravity: 0.3,
            maxBlastForce: 40,
            minBlastForce: 12,
            colors: [
              theme.colorScheme.primary,
              BoggleColors.youGreen,
              BoggleColors.medalGold,
              BoggleColors.medalSilver,
              BoggleColors.medalBronze,
            ],
          ),
        ),
      ],
    );
  }
}

// ----------------------------------------------------------------- sketchit

/// SketchIt play view: canvas for the drawer, guess input for everyone else.
class SketchResultsBanner extends StatelessWidget {
  const SketchResultsBanner({super.key, required this.game});

  final Game game;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text(
      game.sketch?.solved == true
          ? 'THE WORD WAS "${game.sketch?.word.toUpperCase()}"'
          : 'TIME IS UP - THE WORD WAS "${game.sketch?.word.toUpperCase()}"',
      textAlign: TextAlign.center,
      style: theme.textTheme.headlineSmall?.copyWith(
        color: theme.colorScheme.primary,
        fontWeight: FontWeight.bold,
      ),
    );
  }
}

// -------------------------------------------------------------------- chess

/// Capture Chess play view: tap a piece, then a highlighted square.
class ChessResultsBanner extends StatelessWidget {
  const ChessResultsBanner({super.key, required this.game});

  final Game game;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final winner = game.chess?.winner;
    return Text(
      (winner ?? '').isEmpty
          ? 'GAME ABANDONED'
          : winner == 'white'
              ? 'WHITE WINS - KING CAPTURED!'
              : 'BLACK WINS - KING CAPTURED!',
      textAlign: TextAlign.center,
      style: theme.textTheme.headlineSmall?.copyWith(
        color: theme.colorScheme.primary,
        fontWeight: FontWeight.bold,
      ),
    );
  }
}

/// Score ranking card shared by sketch/chess results.
class _ResultsScoreCard extends StatelessWidget {
  const _ResultsScoreCard({required this.ranked});

  final List<Player> ranked;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            for (var i = 0; i < ranked.length; i++)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  children: [
                    if (i < 3)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: Icon(
                          Icons.emoji_events,
                          size: 22,
                          color: const [
                            BoggleColors.medalGold,
                            BoggleColors.medalSilver,
                            BoggleColors.medalBronze,
                          ][i],
                        ),
                      )
                    else
                      SizedBox(
                        width: 30,
                        child: Text(
                          '${i + 1}.',
                          style: theme.textTheme.titleMedium,
                        ),
                      ),
                    Expanded(
                      child: Text(
                        '${ranked[i].name}${ranked[i].isMe ? ' (you)' : ''}',
                        style: ranked[i].isMe
                            ? const TextStyle(
                                color: BoggleColors.youGreen,
                                fontWeight: FontWeight.bold,
                              )
                            : theme.textTheme.titleMedium,
                      ),
                    ),
                    Text(
                      '${ranked[i].score} pts',
                      style: theme.textTheme.titleMedium,
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------- go

/// Go (9x9) play view: tap an intersection to place a stone.
class GoResultsBanner extends StatelessWidget {
  const GoResultsBanner({super.key, required this.game});

  final Game game;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final g = game;
    final s = GoGame.score(GoGame.replay(g.go!.moves).board);
    final text = switch (g.go!.winner) {
      'black' => 'BLACK WINS',
      'white' => 'WHITE WINS',
      'draw' => 'DRAW',
      _ => 'GAME OVER',
    };
    return Column(
      children: [
        Text(
          text,
          textAlign: TextAlign.center,
          style: theme.textTheme.headlineSmall?.copyWith(
            color: theme.colorScheme.primary,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'BLACK ${s.black} AREA · WHITE ${s.white} AREA',
          style: theme.textTheme.titleMedium,
        ),
      ],
    );
  }
}

// -------------------------------------------------------------- word tiles

/// Word Tiles play view: rack chips + board, tap-tap to place tiles.
class WtResultsBanner extends StatelessWidget {
  const WtResultsBanner({super.key, required this.game});

  final Game game;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final g = game;
    String nameOf(String id) =>
        g.players.where((p) => p.id == id).firstOrNull?.name ?? id;
    final winnerName = g.wt!.winner == 'draw' || g.wt!.winner.isEmpty
        ? 'Draw'
        : nameOf(g.wt!.winner);
    return Column(
      children: [
        Text(
          g.wt!.winner == 'draw' ? 'DRAW' : '$winnerName WINS',
          textAlign: TextAlign.center,
          style: theme.textTheme.headlineSmall?.copyWith(
            color: theme.colorScheme.primary,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          [
            for (var i = 0; i < g.wt!.seats.length; i++)
              '${nameOf(g.wt!.seats[i])} ${g.wt!.scoreOf(i)}',
          ].join(' · '),
          style: theme.textTheme.titleMedium,
        ),
      ],
    );
  }
}

