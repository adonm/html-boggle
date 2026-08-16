/// Widgets shared across screens: ready/start controls and the chat panel.
library;

import 'package:flutter/material.dart';

import '../game.dart';
import '../theme.dart';


const double cardRadius = 12;

class ReadyStartControls extends StatelessWidget {
  const ReadyStartControls({
    super.key,
    required this.game,
    required this.startLabel,
  });

  final Game game;
  final String startLabel;

  @override
  Widget build(BuildContext context) {
    final g = game;
    if (g.allReady) {
      return FilledButton.icon(
        onPressed: g.startRound,
        style: FilledButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 14),
        ),
        icon: const Icon(Icons.play_arrow),
        label: Text(startLabel),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FilledButton.tonalIcon(
          onPressed: g.toggleReady,
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 14),
          ),
          icon: Icon(g.me?.ready == true ? Icons.check_circle : Icons.check_circle_outline),
          label: Text(g.me?.ready == true ? 'READY ✓' : 'READY'),
        ),
        const SizedBox(height: 6),
        Text(
          'waiting for everyone... ${g.readyCount}/${g.players.length} ready',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }
}

/// The room chat: message list + input. Used inline in the room view and in
/// a bottom sheet during play.
class ChatPanel extends StatefulWidget {
  const ChatPanel({super.key, required this.game});

  final Game game;

  @override
  State<ChatPanel> createState() => _ChatPanelState();
}

class _ChatPanelState extends State<ChatPanel> {
  final TextEditingController _input = TextEditingController();
  final ScrollController _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    widget.game.addListener(_onGame);
  }

  @override
  void dispose() {
    widget.game.removeListener(_onGame);
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _onGame() {
    // Keep pinned to the newest message, unless the user scrolled up.
    if (!_scroll.hasClients) return;
    final atBottom = _scroll.position.maxScrollExtent - _scroll.position.pixels < 40;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (atBottom && _scroll.hasClients) {
        _scroll.jumpTo(_scroll.position.maxScrollExtent);
      }
    });
  }

  void _send() {
    final text = _input.text;
    if (text.trim().isEmpty) return;
    widget.game.sendChat(text);
    _input.clear();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final g = widget.game;
    return Column(
      children: [
        Expanded(
          child: g.chat.isEmpty
              ? Center(
                  child: Text(
                    'room chat - say hi',
                    style: theme.textTheme.bodySmall,
                  ),
                )
              : ListView.builder(
                  controller: _scroll,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  itemCount: g.chat.length,
                  itemBuilder: (context, i) {
                    final m = g.chat[i];
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 3),
                      child: RichText(
                        text: TextSpan(
                          style: theme.textTheme.bodySmall,
                          children: [
                            TextSpan(
                              text: '${m.name}  ',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: m.fromMe
                                    ? BoggleColors.youGreen
                                    : theme.colorScheme.primary,
                              ),
                            ),
                            TextSpan(text: m.text),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
        Padding(
          padding: const EdgeInsets.all(6),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _input,
                  // iOS Safari auto-zooms into focused inputs smaller than 16px.
                  style: const TextStyle(fontSize: 16),
                  decoration: const InputDecoration(
                    labelText: 'Chat message',
                    hintText: 'message',
                  ),
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => _send(),
                ),
              ),
              const SizedBox(width: 6),
              IconButton.filled(
                tooltip: 'Send message',
                icon: const Icon(Icons.send),
                onPressed: _send,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ------------------------------------------------------------------- room

