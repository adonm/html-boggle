/// The room: player list, game picker with guide card, ready/start, chat.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../game.dart';
import '../net.dart';
import '../theme.dart';
import 'home.dart';
import 'shared.dart';


class GameModePicker extends StatelessWidget {
  const GameModePicker({super.key, required this.game});

  final Game game;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('GAME', style: theme.textTheme.labelMedium),
        const SizedBox(height: 6),
        DropdownMenu<GameMode>(
          initialSelection: game.mode,
          width: 280,
          label: const Text('game'),
          inputDecorationTheme: const InputDecorationTheme(
            border: OutlineInputBorder(),
            isDense: true,
          ),
          onSelected: (m) {
            if (m != null) game.setMode(m);
          },
          dropdownMenuEntries: [
            for (final m in GameMode.values)
              DropdownMenuEntry(
                value: m,
                label: '${m.title}${m.implemented ? '' : '  (soon)'}',
                leadingIcon: Icon(_modeIcon(m)),
              ),
          ],
        ),
        const SizedBox(height: 8),
        _ModeGuide(mode: game.mode),
      ],
    );
  }

  static IconData _modeIcon(GameMode m) => switch (m) {
        GameMode.boggle => Icons.grid_4x4,
        GameMode.scattergories => Icons.abc,
        GameMode.sketchit => Icons.brush,
        GameMode.chess => Icons.sports_esports,
        GameMode.go => Icons.blur_circular,
        GameMode.wordtiles => Icons.view_module,
      };
}

/// Short description + how-to guide for the selected game.
class _ModeGuide extends StatelessWidget {
  const _ModeGuide({required this.mode});

  final GameMode mode;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            mode.title,
            style: theme.textTheme.titleSmall,
          ),
          const SizedBox(height: 4),
          Text(mode.description, style: theme.textTheme.bodySmall),
          const SizedBox(height: 6),
          Text(
            'HOW TO PLAY: ${mode.howTo}',
            style: theme.textTheme.bodySmall?.copyWith(fontStyle: FontStyle.italic),
          ),
        ],
      ),
    );
  }
}

/// Ready / start controls: everyone readies up, then ANYONE can start.
class RoomScreen extends StatelessWidget {
  const RoomScreen({super.key, required this.game});

  final Game game;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final g = game;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              'ROOM  ${g.room}',
                              textAlign: TextAlign.center,
                              style: theme.textTheme.headlineMedium?.copyWith(
                                color: theme.colorScheme.primary,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          const ThemeMenu(),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'players who enter this code join the same game',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodySmall,
                      ),
                      const SizedBox(height: 18),
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              for (final p in g.players)
                                ListTile(
                                  dense: true,
                                  leading: Icon(
                                    p.isMe ? Icons.person : Icons.person_outline,
                                    color: p.isMe
                                        ? BoggleColors.youGreen
                                        : theme.colorScheme.onSurfaceVariant,
                                  ),
                                  title: Text(
                                    (p.isMe ? '${p.name} (you)' : (p.name.isEmpty ? 'connecting...' : p.name)) +
                                        (p.id == g.hostId ? '  · LEADER' : ''),
                                  ),
                                  trailing: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        p.ready ? 'ready ✓' : '…',
                                        style: theme.textTheme.bodySmall?.copyWith(
                                          color: p.ready
                                              ? BoggleColors.youGreen
                                              : theme.colorScheme.onSurfaceVariant,
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Text('${p.score}'),
                                    ],
                                  ),
                                ),
                              Text(
                                '${g.players.length} player${g.players.length == 1 ? '' : 's'} in room',
                                textAlign: TextAlign.center,
                                style: theme.textTheme.bodySmall,
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 18),
                      GameModePicker(game: g),
                      const SizedBox(height: 12),
                      ReadyStartControls(game: g, startLabel: 'START ROUND'),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () async {
                                final url = _roomLink(g);
                                final shared = await shareLink(
                                  title: 'Boggle room ${g.room}',
                                  url: url,
                                );
                                g.showToast(shared ? 'Shared!' : 'Link copied - share it!');
                              },
                              icon: const Icon(Icons.link),
                              label: const Text('SHARE LINK'),
                            ),
                          ),
                          const SizedBox(width: 8),
                          IconButton.outlined(
                            tooltip: 'Show QR code',
                            onPressed: () => _showQr(context, g),
                            icon: const Icon(Icons.qr_code_2),
                          ),
                        ],
                      ),
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
              const SizedBox(height: 12),
              SizedBox(
                height: 220,
                child: Card(child: ChatPanel(game: g)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// -------------------------------------------------------------------- play


/// The room's join link.
String _roomLink(Game g) => (Uri.tryParse(pageHref) ?? Uri.base)
    .replace(queryParameters: {'room': g.room})
    .removeFragment()
    .toString();

/// QR code dialog: scan to join from another device.
void _showQr(BuildContext context, Game g) {
  final url = _roomLink(g);
  showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text('Room ${g.room}'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          QrImageView(
            data: url,
            size: 220,
            backgroundColor: Colors.white,
            semanticsLabel: 'room join QR code',
          ),
          const SizedBox(height: 10),
          Text(url, style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () async {
            await Clipboard.setData(ClipboardData(text: url));
            if (context.mounted) g.showToast('Link copied - share it!');
          },
          child: const Text('COPY LINK'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('DONE'),
        ),
      ],
    ),
  );
}
