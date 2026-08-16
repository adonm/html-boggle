/// Scattergories play view: letter header, submit box, submissions feed.
library;

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../game.dart';
import '../home.dart';
import '../shared.dart';


class ScatterPlayBody extends StatefulWidget {
  const ScatterPlayBody({super.key, required this.game});

  final Game game;

  @override
  State<ScatterPlayBody> createState() => _ScatterPlayBodyState();
}

class _ScatterPlayBodyState extends State<ScatterPlayBody> {
  final TextEditingController _input = TextEditingController();

  Game get game => widget.game;

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  String _fmt(int ms) {
    final s = (ms / 1000).ceil();
    return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
  }

  void _submit() {
    game.scatter?.submit(_input.text);
    _input.clear();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final g = game;
    final remaining = g.remainingMs();
    final urgent = remaining < 10000;
    final timerText = Text(
      _fmt(remaining),
      style: theme.textTheme.headlineSmall?.copyWith(
        color: urgent ? theme.colorScheme.error : theme.colorScheme.primary,
        fontFeatures: const [FontFeature.tabularFigures()],
        fontWeight: FontWeight.bold,
      ),
    );
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(cardRadius),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'SCATTERGORIES · ROUND ${g.round}',
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleMedium,
                      ),
                    ),
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
              ),
              const SizedBox(height: 4),
              ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: LinearProgressIndicator(
                  value: remaining / roundMs,
                  minHeight: 6,
                  color: urgent ? theme.colorScheme.error : theme.colorScheme.primary,
                  backgroundColor: theme.colorScheme.surfaceContainerHighest,
                ),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(18),
                          child: Column(
                            children: [
                              Text(
                                g.scatter!.letter,
                                style: theme.textTheme.displayLarge?.copyWith(
                                  fontSize: 88,
                                  color: theme.colorScheme.primary,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'words must start with this letter',
                                style: theme.textTheme.bodySmall,
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _input,
                              style: const TextStyle(fontSize: 16),
                              decoration: const InputDecoration(
                                labelText: 'Scattergories word',
                                hintText: 'type a word...',
                              ),
                              textInputAction: TextInputAction.send,
                              autocorrect: false,
                              enableSuggestions: false,
                              onSubmitted: (_) => _submit(),
                            ),
                          ),
                          const SizedBox(width: 6),
                          IconButton.filled(
                            tooltip: 'Submit word',
                            icon: const Icon(Icons.arrow_forward),
                            onPressed: _submit,
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text('SUBMITTED', style: theme.textTheme.labelMedium),
                              const SizedBox(height: 6),
                              for (final p in g.players)
                                Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 2),
                                  child: Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          p.isMe ? '${p.name} (you)' : (p.name.isEmpty ? '...' : p.name),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      Text('${g.scatter!.submissions[p.id]?.length ?? 0} words'),
                                    ],
                                  ),
                                ),
                              const Divider(),
                              Wrap(
                                spacing: 6,
                                runSpacing: 6,
                                children: [
                                  for (final w in (g.scatter!.submissions[g.meId] ?? const <String>[]).reversed)
                                    Chip(
                                      label: Text(w.toUpperCase()),
                                      visualDensity: VisualDensity.compact,
                                    ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
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

// ---------------------------------------------------- scattergories results

