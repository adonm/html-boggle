/// Boggle play screen: board, path, timer, claim feed.
library;

import 'package:confetti/confetti.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../game.dart';
import '../../theme.dart';
import '../home.dart';
import '../shared.dart';
import 'chess.dart';
import 'go.dart';
import 'scatter.dart';
import 'sketch.dart';
import 'wordtiles.dart';


class PlayScreen extends StatefulWidget {
  const PlayScreen({super.key, required this.game});

  final Game game;

  @override
  State<PlayScreen> createState() => _PlayScreenState();
}

class _PlayScreenState extends State<PlayScreen> {
  final ConfettiController _confetti = ConfettiController(duration: 900.ms);
  int _lastAward = 0;

  Game get game => widget.game;

  @override
  void initState() {
    super.initState();
    game.addListener(_onGame);
  }

  @override
  void dispose() {
    game.removeListener(_onGame);
    _confetti.dispose();
    super.dispose();
  }

  void _onGame() {
    if (game.awardPulse != _lastAward) {
      _lastAward = game.awardPulse;
      _confetti.play();
    }
  }

  String _fmt(int ms) {
    final s = (ms / 1000).ceil();
    return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final g = game;
    if (g.mode == GameMode.scattergories) {
      return ScatterPlayBody(game: g);
    }
    if (g.mode == GameMode.sketchit) {
      return SketchPlayBody(game: g);
    }
    if (g.mode == GameMode.chess) {
      return ChessPlayBody(game: g);
    }
    if (g.mode == GameMode.go) {
      return GoPlayBody(game: g);
    }
    if (g.mode == GameMode.wordtiles) {
      return WtPlayBody(game: g);
    }
    final remaining = g.remainingMs();
    final urgent = remaining < 10000;
    return Stack(
      children: [
        Positioned.fill(
          child: Center(
            child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 900),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= 720;
            final timerText = Text(
              _fmt(remaining),
              style: theme.textTheme.headlineSmall?.copyWith(
                color: urgent ? theme.colorScheme.error : theme.colorScheme.primary,
                fontFeatures: const [FontFeature.tabularFigures()],
                fontWeight: FontWeight.bold,
              ),
            );
            final header = Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(cardRadius),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'ROOM ${g.room} · ROUND ${g.round}',
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium,
                    ),
                  ),
                  // pulse the clock when time runs short
                  if (urgent)
                    Animate(
                      onPlay: (c) => c.loop(reverse: true),
                      effects: [
                        ScaleEffect(
                          begin: const Offset(1.0, 1.0),
                          end: const Offset(1.12, 1.12),
                          duration: 550.ms,
                          curve: Curves.easeInOut,
                        ),
                      ],
                      child: timerText,
                    )
                  else
                    timerText,
                  const SizedBox(width: 4),
                  IconButton(
                    tooltip: 'Room chat',
                    icon: const Icon(Icons.forum_outlined),
                    onPressed: () => showModalBottomSheet<void>(
                      context: context,
                      isScrollControlled: true,
                      showDragHandle: true,
                      builder: (sheetContext) => Padding(
                        padding: EdgeInsets.only(
                          bottom: MediaQuery.viewInsetsOf(sheetContext).bottom,
                        ),
                        child: SizedBox(
                          height: MediaQuery.sizeOf(sheetContext).height * 0.55,
                          child: ChatPanel(game: g),
                        ),
                      ),
                    ),
                  ),
                  const ThemeMenu(),
                ],
              ),
            );
            final progress = ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(
                value: remaining / roundMs,
                minHeight: 6,
                color: urgent ? theme.colorScheme.error : theme.colorScheme.primary,
                backgroundColor: theme.colorScheme.surfaceContainerHighest,
              ),
            );
            final wordText = Text(
              g.boggle!.currentWord.isEmpty
                  ? 'tap tiles to spell a word'
                  : g.boggle!.currentWord.toUpperCase(),
              textAlign: TextAlign.center,
              style: theme.textTheme.headlineSmall?.copyWith(
                color: g.boggle!.currentWord.isEmpty
                    ? theme.colorScheme.onSurfaceVariant
                    : theme.colorScheme.primary,
                fontWeight: FontWeight.bold,
                letterSpacing: 3,
              ),
            );
            // shake the word when a submission is rejected
            final wordWidget = g.wordAttempts > 0
                ? Animate(
                    key: ValueKey('shake${g.wordAttempts}'),
                    effects: [
                      ShakeEffect(
                        duration: 420.ms,
                        hz: 4,
                        offset: const Offset(5, 0),
                        curve: Curves.easeInOut,
                      ),
                    ],
                    child: wordText,
                  )
                : wordText;
            final actions = Wrap(
              alignment: WrapAlignment.center,
              spacing: 6,
              runSpacing: 6,
              children: [
                FilledButton.icon(
                  onPressed: g.boggle!.currentWord.length >= 3 ? g.boggle!.submitWord : null,
                  icon: const Icon(Icons.arrow_forward),
                  label: const Text('SUBMIT'),
                ),
                OutlinedButton.icon(
                  onPressed: g.boggle!.path.isEmpty ? null : g.boggle!.popTile,
                  icon: const Icon(Icons.arrow_back),
                  label: const Text('UNDO'),
                ),
                OutlinedButton.icon(
                  onPressed: g.boggle!.path.isEmpty ? null : g.boggle!.clearPath,
                  icon: const Icon(Icons.backspace_outlined),
                  label: const Text('CLEAR'),
                ),
              ],
            );

            if (wide) {
              return Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    header,
                    const SizedBox(height: 4),
                    progress,
                    const SizedBox(height: 12),
                    Expanded(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(
                            flex: 3,
                            child: Column(
                              children: [
                                Expanded(child: _buildBoard(theme, g)),
                                const SizedBox(height: 12),
                                wordWidget,
                                const SizedBox(height: 6),
                                actions,
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),
                          SizedBox(width: 252, child: _buildPlayers(theme, g)),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            }

            // phone layout: stacked, page scrolls
            return SingleChildScrollView(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  header,
                  const SizedBox(height: 4),
                  progress,
                  const SizedBox(height: 12),
                  AspectRatio(
                    aspectRatio: 1,
                    child: _buildBoard(theme, g),
                  ),
                  const SizedBox(height: 12),
                  wordWidget,
                  const SizedBox(height: 6),
                  actions,
                  const SizedBox(height: 12),
                  _buildPlayers(theme, g, scrollable: false),
                ],
              ),
            );
          },
        ),
      ),
        ),
      ),
      Align(
        alignment: Alignment.topCenter,
        child: ConfettiWidget(
          confettiController: _confetti,
          blastDirectionality: BlastDirectionality.explosive,
          emissionFrequency: 0.04,
          numberOfParticles: 30,
          gravity: 0.25,
          maxBlastForce: 32,
          minBlastForce: 8,
          colors: [
            theme.colorScheme.primary,
            BoggleColors.youGreen,
            BoggleColors.medalGold,
            theme.colorScheme.error,
          ],
        ),
      ),
    ]);
  }

  Widget _buildBoard(ThemeData theme, Game g) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return GridView.count(
          crossAxisCount: 4,
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
          physics: const NeverScrollableScrollPhysics(),
          children: [
            for (var i = 0; i < 16; i++) _tile(theme, g, i),
          ],
        );
      },
    );
  }

  Widget _tile(ThemeData theme, Game g, int i) {
    final order = g.boggle!.path.indexOf(i);
    final selected = order >= 0;
    final letter = g.boggle!.board.isEmpty ? '' : g.boggle!.board[i].toUpperCase();
    return Animate(
      // deal the tiles in at the start of every round
      key: ValueKey('tile$i-${g.roundEpoch}'),
      effects: [
        ScaleEffect(
          begin: const Offset(0.4, 0.4),
          end: const Offset(1, 1),
          duration: 420.ms,
          curve: Curves.easeOutBack,
          delay: (i * 28).ms,
        ),
        FadeEffect(
          begin: 0.0,
          end: 1.0,
          duration: 250.ms,
          delay: (i * 28).ms,
        ),
      ],
      child: Semantics(
        label: 'Tile ${i + 1} letter $letter',
        button: true,
        selected: selected,
        child: Material(
          color: selected
              ? theme.colorScheme.primary
              : theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(cardRadius),
          child: InkWell(
            borderRadius: BorderRadius.circular(cardRadius),
            onTap: () => g.boggle!.tapTile(i),
            child: AnimatedScale(
              scale: selected ? 1.07 : 1.0,
              duration: 110.ms,
              curve: Curves.easeOut,
              child: SizedBox.expand(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      letter,
                      style: theme.textTheme.headlineMedium?.copyWith(
                        color: selected
                            ? theme.colorScheme.onPrimary
                            : theme.colorScheme.onSurface,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    if (selected)
                      Text(
                        '${order + 1}',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onPrimary,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPlayers(ThemeData theme, Game g, {bool scrollable = true}) {
    final me = g.me;
    final words = Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final w in (me?.words.toList().reversed ?? const Iterable<String>.empty()))
          Chip(
            label: Text(w.toUpperCase()),
            visualDensity: VisualDensity.compact,
          ),
      ],
    );
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('PLAYERS', style: theme.textTheme.labelMedium),
            const SizedBox(height: 6),
            for (final p in g.players)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        (p.isMe ? '${p.name} (you)' : (p.name.isEmpty ? '...' : p.name)) +
                            (p.id == g.hostId ? ' · LEADER' : ''),
                        overflow: TextOverflow.ellipsis,
                        style: p.isMe
                            ? const TextStyle(
                                color: BoggleColors.youGreen,
                                fontWeight: FontWeight.bold,
                              )
                            : null,
                      ),
                    ),
                    Text(
                      '${p.score}',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ),
              ),
            const Divider(),
            Text(
              'YOUR WORDS (${me?.words.length ?? 0})',
              style: theme.textTheme.labelMedium,
            ),
            const SizedBox(height: 6),
            if (scrollable)
              Flexible(child: SingleChildScrollView(child: words))
            else
              words,
          ],
        ),
      ),
    );
  }
}

// ----------------------------------------------------- scattergories play

