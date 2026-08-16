/// The play-screen navbar: room context (code + player count), a
/// how-to-play guide dialog, and a leave button - so any game can be
/// exited and another one started without leaving the tab.
library;

import 'package:flutter/material.dart';

import '../game.dart';

class GameNavBar extends StatelessWidget {
  const GameNavBar({super.key, required this.game});

  final Game game;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final g = game;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
      ),
      child: Row(
        children: [
          Icon(Icons.groups_outlined,
              size: 18, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 6),
          Text(
            'ROOM ${g.room} · ${g.players.length} player${g.players.length == 1 ? '' : 's'}',
            style: theme.textTheme.titleSmall,
          ),
          const Spacer(),
          IconButton(
            tooltip: 'How to play',
            icon: const Icon(Icons.help_outline),
            onPressed: () => showGameGuide(context, g),
          ),
          TextButton.icon(
            onPressed: g.leaveRoom,
            icon: const Icon(Icons.logout, size: 18),
            label: const Text('LEAVE'),
          ),
        ],
      ),
    );
  }
}

/// The how-to-play dialog for the current game: description + guide,
/// available from the play-screen navbar.
void showGameGuide(BuildContext context, Game g) {
  final theme = Theme.of(context);
  showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(g.mode.title),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(g.mode.description, style: theme.textTheme.bodyMedium),
            const SizedBox(height: 10),
            Text(
              'HOW TO PLAY: ${g.mode.howTo}',
              style: theme.textTheme.bodyMedium
                  ?.copyWith(fontStyle: FontStyle.italic),
            ),
          ],
        ),
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('DONE'),
        ),
      ],
    ),
  );
}
