/// Lobby (join form) and the joining splash.
library;

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:url_launcher/url_launcher.dart';

import '../game.dart';
import '../net.dart';
import '../widgets/game_icon.dart';
import '../widgets/huddle_mark.dart';
import 'home.dart';


class LobbyScreen extends StatefulWidget {
  const LobbyScreen({super.key, required this.game});

  final Game game;

  @override
  State<LobbyScreen> createState() => _LobbyScreenState();
}

class _LobbyScreenState extends State<LobbyScreen> {
  final TextEditingController _name = TextEditingController();
  final TextEditingController _room = TextEditingController();

  @override
  void initState() {
    super.initState();
    // Deep links: /?room=code prefills the room field. Read from the real
    // page URL - Uri.base is the <base href> and has no query string.
    final url = Uri.tryParse(pageHref);
    final room = url?.queryParameters['room'];
    if (room != null && room.isNotEmpty) {
      _room.text = room;
      widget.game.showToast('Room $room - tap JOIN to enter');
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _room.dispose();
    super.dispose();
  }

  void _join() {
    widget.game.join(roomCode: _room.text, name: _name.text);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: SingleChildScrollView(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Card(
            margin: const EdgeInsets.all(18),
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Huddle mark + title
                  Center(
                    child: Animate(
                      onPlay: (c) => c.loop(reverse: true),
                      effects: [
                        ScaleEffect(
                          begin: const Offset(0.97, 0.97),
                          end: const Offset(1.02, 1.02),
                          duration: 1800.ms,
                          curve: Curves.easeInOut,
                        ),
                      ],
                      child: const HuddleMark(size: 84),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'HUDDLE',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.displaySmall?.copyWith(
                      color: theme.colorScheme.primary,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 6,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'six party games · one room code · zero servers',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall,
                  ),
                  const SizedBox(height: 18),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _name,
                          // iOS Safari auto-zooms into focused inputs smaller
                          // than 16px; keep the field text at 16px.
                          style: const TextStyle(fontSize: 16),
                          decoration: const InputDecoration(
                            labelText: 'Your name',
                            hintText: 'optional - we can pick one',
                          ),
                          textInputAction: TextInputAction.next,
                          onSubmitted: (_) =>
                              FocusScope.of(context).nextFocus(),
                        ),
                      ),
                      const SizedBox(width: 6),
                      IconButton(
                        tooltip: 'Random name',
                        icon: const Icon(Icons.refresh),
                        onPressed: () => setState(
                          () => _name.text = widget.game.randomName(),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _room,
                    style: const TextStyle(fontSize: 16),
                    decoration: const InputDecoration(
                      labelText: 'Room code',
                      hintText: 'same code = same game',
                    ),
                    textInputAction: TextInputAction.go,
                    autocorrect: false,
                    enableSuggestions: false,
                    onSubmitted: (_) => _join(),
                  ),
                  const SizedBox(height: 18),
                  FilledButton(
                    onPressed: _join,
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: const Text('JOIN ROOM'),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Anyone entering the same room code lands on the same '
                    'gossip channel. Share the link from the room view.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall,
                  ),
                  const SizedBox(height: 18),
                  const Divider(),
                  const SizedBox(height: 12),
                  Text(
                    'GAMES',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.labelMedium,
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final m in GameMode.values)
                        Chip(
                          avatar: gameIcon(m, size: 18),
                          label: Text(m.title),
                          visualDensity: VisualDensity.compact,
                        ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  const Divider(),
                  const SizedBox(height: 12),
                  Text(
                    'APPEARANCE',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.labelMedium,
                  ),
                  const SizedBox(height: 8),
                  const AppearanceSection(),
                  const SizedBox(height: 16),
                  OutlinedButton.icon(
                    onPressed: () => launchUrl(
                      Uri.parse('https://github.com/adonm/html-boggle'),
                    ),
                    icon: const Icon(Icons.code, size: 18),
                    label: const Text('github.com/adonm/html-boggle'),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Apache-2.0 · no servers, just relays',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- joining

class JoiningScreen extends StatelessWidget {
  const JoiningScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(),
          SizedBox(height: 18),
          Text('Joining room...'),
          SizedBox(height: 6),
          Text('connecting peers through iroh gossip'),
        ],
      ),
    );
  }
}

// -------------------------------------------------------------------- chat

/// Game picker (the round starter's choice wins; the start message carries it).
