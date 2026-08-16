/// Screens: lobby, joining, room, play, results. Styled by the Yaru themes
/// with semantics labels so screen readers and tests can navigate the game.
/// Layouts adapt to phone-sized viewports (stacked board, scrollable panels).
library;

import 'dart:async';

import 'package:confetti/confetti.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import 'chess.dart';
import 'game.dart';
import 'go.dart';
import 'net.dart';
import 'theme.dart';
import 'wordtiles.dart';

const double _cardRadius = 12;

// -------------------------------------------------------------------- home

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.game});

  final Game game;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  String _lastToast = '';

  @override
  void initState() {
    super.initState();
    widget.game.addListener(_onGame);
  }

  @override
  void dispose() {
    widget.game.removeListener(_onGame);
    super.dispose();
  }

  void _onGame() {
    final g = widget.game;
    if (g.toast.isNotEmpty && g.toast != _lastToast) {
      _lastToast = g.toast;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(g.toast),
            duration: const Duration(milliseconds: 2200),
            behavior: SnackBarBehavior.floating,
          ),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final g = widget.game;
    final theme = Theme.of(context);
    return AnimatedBuilder(
      animation: g,
      builder: (context, _) {
        final Widget screen = switch (g.phase) {
          Phase.lobby => LobbyScreen(game: g),
          Phase.joining => const JoiningScreen(),
          Phase.room => RoomScreen(game: g),
          Phase.play => PlayScreen(game: g),
          Phase.results => ResultsScreen(game: g),
        };
        return Scaffold(
          body: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.30),
                  theme.scaffoldBackgroundColor,
                ],
                stops: const [0.0, 0.35],
              ),
            ),
            child: SafeArea(
              child: AnimatedSwitcher(
                duration: 300.ms,
                switchInCurve: Curves.easeOut,
                switchOutCurve: Curves.easeIn,
                transitionBuilder: (child, animation) => FadeTransition(
                  opacity: animation,
                  child: SlideTransition(
                    position: Tween<Offset>(
                      begin: const Offset(0, 0.03),
                      end: Offset.zero,
                    ).animate(animation),
                    child: child,
                  ),
                ),
                child: KeyedSubtree(key: ValueKey(g.phase), child: screen),
              ),
            ),
          ),
        );
      },
    );
  }
}

// -------------------------------------------------------------- appearance

/// Yaru accent dots + dark/light switch. Used in the lobby and in the theme
/// bottom sheet.
class AppearanceSection extends StatelessWidget {
  const AppearanceSection({super.key});

  @override
  Widget build(BuildContext context) {
    final themes = ThemeController.instance;
    final scheme = Theme.of(context).colorScheme;
    return ListenableBuilder(
      listenable: themes,
      builder: (context, _) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.center,
            children: [
              for (final variant in themes.accents)
                Semantics(
                  label: 'Accent ${variant.name}',
                  button: true,
                  selected: themes.variant == variant,
                  child: Tooltip(
                    message: variant.name,
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: () => themes.setVariant(variant),
                      child: Container(
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: variant.color,
                          border: Border.all(
                            color: themes.variant == variant
                                ? scheme.onSurface
                                : Colors.transparent,
                            width: 2,
                          ),
                        ),
                        child: themes.variant == variant
                            ? const Icon(Icons.check, size: 18, color: Colors.white)
                            : null,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment(value: false, label: Text('Dark')),
              ButtonSegment(value: true, label: Text('Light')),
            ],
            selected: {themes.light},
            showSelectedIcon: false,
            onSelectionChanged: (sel) => themes.setLight(sel.first),
          ),
        ],
      ),
    );
  }
}

/// Quick theme switcher: opens a bottom sheet with the appearance settings.
class ThemeMenu extends StatelessWidget {
  const ThemeMenu({super.key});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: 'Theme',
      icon: const Icon(Icons.palette_outlined),
      onPressed: () => showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        builder: (context) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'APPEARANCE',
                  style: Theme.of(context).textTheme.labelMedium,
                ),
                const SizedBox(height: 12),
                const AppearanceSection(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ------------------------------------------------------------------- lobby

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
                  // Dice mark + title
                  Center(
                    child: Animate(
                      onPlay: (c) => c.loop(reverse: true),
                      effects: [
                        RotateEffect(
                          begin: -0.04,
                          end: 0.04,
                          duration: 1400.ms,
                          curve: Curves.easeInOut,
                        ),
                      ],
                      child: Container(
                        width: 72,
                        height: 72,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              theme.colorScheme.primary,
                              theme.colorScheme.primary.withValues(alpha: 0.65),
                            ],
                          ),
                          borderRadius: BorderRadius.circular(18),
                        ),
                        child: Center(
                          child: Text(
                            'B',
                            style: theme.textTheme.displaySmall?.copyWith(
                              color: theme.colorScheme.onPrimary,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'BOGGLE',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.displaySmall?.copyWith(
                      color: theme.colorScheme.primary,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 6,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'multiplayer word game · iroh gossip · no servers',
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
                    'APPEARANCE',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.labelMedium,
                  ),
                  const SizedBox(height: 8),
                  const AppearanceSection(),
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
                      OutlinedButton.icon(
                        onPressed: () async {
                          final url = (Uri.tryParse(pageHref) ?? Uri.base)
                              .replace(queryParameters: {'room': g.room})
                              .removeFragment()
                              .toString();
                          final shared = await shareLink(
                            title: 'Boggle room ${g.room}',
                            url: url,
                          );
                          g.showToast(shared ? 'Shared!' : 'Link copied - share it!');
                        },
                        icon: const Icon(Icons.link),
                        label: const Text('SHARE LINK'),
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
                borderRadius: BorderRadius.circular(_cardRadius),
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
          borderRadius: BorderRadius.circular(_cardRadius),
          child: InkWell(
            borderRadius: BorderRadius.circular(_cardRadius),
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
                  borderRadius: BorderRadius.circular(_cardRadius),
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
class SketchPlayBody extends StatefulWidget {
  const SketchPlayBody({super.key, required this.game});

  final Game game;

  @override
  State<SketchPlayBody> createState() => _SketchPlayBodyState();
}

class _SketchPlayBodyState extends State<SketchPlayBody> {
  final TextEditingController _guess = TextEditingController();
  final List<Offset> _buf = [];
  Timer? _flush;
  String? _strokeId;

  Game get game => widget.game;

  @override
  void initState() {
    super.initState();
    game.addListener(_onGame);
  }

  @override
  void dispose() {
    game.removeListener(_onGame);
    _flush?.cancel();
    _guess.dispose();
    super.dispose();
  }

  void _onGame() => setState(() {});

  bool get _isDrawer => game.meId == game.sketch?.drawer;

  void _sendBuf(double color, double width) {
    if (_buf.isEmpty || _strokeId == null) return;
    game.sketch?.draw(
      color,
      width,
      [for (final p in _buf) p.dx, for (final p in _buf) p.dy],
      id: _strokeId,
    );
    _buf.clear();
  }

  void _startStroke(Offset p, Size size) {
    if (!_isDrawer) return;
    _flush?.cancel();
    _strokeId = DateTime.now().microsecondsSinceEpoch.toString();
    _buf
      ..clear()
      ..add(Offset(
        p.dx / size.width,
        p.dy / size.height,
      ));
    _sendBuf(_color, _width);
    _flush = Timer.periodic(const Duration(milliseconds: 90), (_) {
      _sendBuf(_color, _width);
    });
  }

  void _extendStroke(Offset p, Size size) {
    if (!_isDrawer || _strokeId == null) return;
    _buf.add(Offset(
      (p.dx / size.width).clamp(0.0, 1.0),
      (p.dy / size.height).clamp(0.0, 1.0),
    ));
  }

  void _endStroke() {
    _flush?.cancel();
    _flush = null;
    if (_strokeId == null) return;
    _sendBuf(_color, _width);
    _strokeId = null;
    _buf.clear();
  }

  double _color = 0xFFFF9800;
  double _width = 0.004;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final g = game;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
          child: Text(
            _isDrawer
                ? 'DRAW: ${g.sketch!.word.toUpperCase()}'
                : 'ANSWER: ${g.sketch!.word.toUpperCase()}',
            textAlign: TextAlign.center,
            style: theme.textTheme.titleLarge?.copyWith(
              color: _isDrawer ? theme.colorScheme.primary : theme.colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        Expanded(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 900, maxHeight: 520),
              child: AspectRatio(
                aspectRatio: 16 / 9,
                child: Card(
                  clipBehavior: Clip.antiAlias,
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final size = Size(
                        constraints.maxWidth,
                        constraints.maxHeight,
                      );
                      return Semantics(
                        label: 'drawing canvas',
                        child: GestureDetector(
                          onPanStart: _isDrawer
                              ? (d) => _startStroke(d.localPosition, size)
                              : null,
                          onPanUpdate: _isDrawer
                              ? (d) => _extendStroke(d.localPosition, size)
                              : null,
                          onPanEnd: _isDrawer ? (_) => _endStroke() : null,
                          child: CustomPaint(
                            size: size,
                            painter: SketchPainter(strokes: g.sketch!.strokes),
                            child: const SizedBox.expand(),
                          ),
                        ),
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
          child: _isDrawer
              ? Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    for (final c in const [
                      0xFFFF9800, 0xFFF44336, 0xFF4CAF50, 0xFF2196F3, 0xFF9C27B0, 0xFF000000,
                    ])
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 3),
                        child: InkWell(
                          onTap: () => setState(() => _color = c.toDouble()),
                          child: Container(
                            width: 26,
                            height: 26,
                            decoration: BoxDecoration(
                              color: Color(c),
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: _color == c.toDouble()
                                    ? theme.colorScheme.primary
                                    : Colors.transparent,
                                width: 3,
                              ),
                            ),
                          ),
                        ),
                      ),
                    const SizedBox(width: 12),
                    OutlinedButton.icon(
                      onPressed: () {
                        game.sketch?.clearCanvas();
                        setState(() {});
                      },
                      icon: const Icon(Icons.cleaning_services, size: 18),
                      label: const Text('CLEAR'),
                    ),
                  ],
                )
              : Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _guess,
                        onSubmitted: _submitGuess,
                        decoration: InputDecoration(
                          hintText: 'type your guess...',
                          isDense: true,
                          border: const OutlineInputBorder(),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      onPressed: () => _submitGuess(_guess.text),
                      child: const Text('GUESS'),
                    ),
                  ],
                ),
        ),
      ],
    );
  }

  void _submitGuess(String text) {
    if (text.trim().isEmpty) return;
    game.sketch?.guess(text);
    _guess.clear();
  }
}

/// Paints SketchIt strokes (normalized 0..1 coordinates).
class SketchPainter extends CustomPainter {
  const SketchPainter({required this.strokes});

  final List<Map<String, dynamic>> strokes;

  @override
  void paint(Canvas canvas, Size size) {
    final white = Paint()..color = Colors.white;
    canvas.drawRect(Offset.zero & size, white);
    for (final s in strokes) {
      final pts = s['pts'];
      if (pts is! List || pts.isEmpty) continue;
      final color = s['color'];
      final width = s['width'];
      final paint = Paint()
        ..color = Color((color is num ? color.toInt() : 0xFF000000))
        ..strokeWidth = ((width is num ? width : 0.004) * size.width).clamp(1.5, 20)
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..style = PaintingStyle.stroke;
      final path = Path();
      for (var i = 0; i < pts.length / 2; i++) {
        final x = (pts[i] as num).toDouble() * size.width;
        final y = (pts[i + pts.length ~/ 2] as num).toDouble() * size.height;
        if (i == 0) {
          path.moveTo(x, y);
        } else {
          path.lineTo(x, y);
        }
      }
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(SketchPainter oldDelegate) =>
      oldDelegate.strokes.length != strokes.length ||
      (strokes.isNotEmpty && oldDelegate.strokes.last != strokes.last);
}

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
class GoPlayBody extends StatefulWidget {
  const GoPlayBody({super.key, required this.game});

  final Game game;

  @override
  State<GoPlayBody> createState() => _GoPlayBodyState();
}

class _GoPlayBodyState extends State<GoPlayBody> {
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

  Widget _cell(int x, int y, double sq, bool myTurn) {
    final coord = GoGame.coord(y * 9 + x);
    return Semantics(
      label: 'go cell $coord',
      button: true,
      child: SizedBox(
        width: sq,
        height: sq,
        child: InkWell(
          onTap: myTurn ? () => game.go?.tryMove(coord) : null,
          child: const SizedBox.expand(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final g = game;
    final r = GoGame.replay(g.go!.moves);
    final myTurn = g.meId == g.go!.turnId;
    final isPlayer = g.meId == g.go!.black || g.meId == g.go!.white;
    final lastIdx = g.go!.moves.isNotEmpty &&
            g.go!.moves.last != 'pass' &&
            g.go!.moves.last != 'resign'
        ? GoGame.sq(g.go!.moves.last)
        : -1;
    String nameOf(String id) =>
        g.players.where((p) => p.id == id).firstOrNull?.name ?? id;
    final turnName = g.go!.blackTurn
        ? (nameOf(g.go!.black).isEmpty ? 'Black' : nameOf(g.go!.black))
        : (nameOf(g.go!.white).isEmpty ? 'White' : nameOf(g.go!.white));
    final blackCount = r.board.where((c) => c == 'B').length;
    final whiteCount = r.board.where((c) => c == 'W').length;
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
              constraints: const BoxConstraints(maxWidth: 520),
              child: AspectRatio(
                aspectRatio: 1,
                child: Card(
                  clipBehavior: Clip.antiAlias,
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final size = Size(
                        constraints.maxWidth,
                        constraints.maxHeight,
                      );
                      final sq = size.width / 9;
                      return Stack(
                        children: [
                          Positioned.fill(
                            child: CustomPaint(
                              size: size,
                              painter: GoPainter(
                                board: r.board,
                                lastIdx: lastIdx,
                                theme: theme,
                              ),
                            ),
                          ),
                          Column(
                            children: [
                              for (var y = 0; y < 9; y++)
                                Row(
                                  children: [
                                    for (var x = 0; x < 9; x++)
                                      _cell(x, y, sq, myTurn),
                                  ],
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
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                'BLACK $blackCount · WHITE $whiteCount',
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(width: 16),
              if (isPlayer) ...[
                FilledButton.tonal(
                  onPressed: myTurn ? g.go!.passTurn : null,
                  child: const Text('PASS'),
                ),
                const SizedBox(width: 8),
                OutlinedButton(
                  onPressed: g.go!.resign,
                  child: const Text('RESIGN'),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// Paints the 9x9 grid, star points, stones, and the last-move marker.
class GoPainter extends CustomPainter {
  const GoPainter({
    required this.board,
    required this.lastIdx,
    required this.theme,
  });

  final List<String> board;
  final int lastIdx;
  final ThemeData theme;

  @override
  void paint(Canvas canvas, Size size) {
    final bg = Paint()..color = theme.colorScheme.surfaceContainerHighest;
    canvas.drawRect(Offset.zero & size, bg);
    final step = size.width / 9;
    final line = Paint()
      ..color = theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.7)
      ..strokeWidth = 1.2;
    for (var i = 0; i < 9; i++) {
      final p = step * (i + 0.5);
      canvas.drawLine(Offset(step / 2, p), Offset(size.width - step / 2, p), line);
      canvas.drawLine(Offset(p, step / 2), Offset(p, size.height - step / 2), line);
    }
    // star points (hoshi)
    final star = Paint()..color = theme.colorScheme.onSurfaceVariant;
    for (final h in const [2, 6]) {
      for (final v in const [2, 6]) {
        canvas.drawCircle(
          Offset(step * (h + 0.5), step * (v + 0.5)),
          step * 0.09,
          star,
        );
      }
    }
    canvas.drawCircle(Offset(step * 4.5, step * 4.5), step * 0.09, star);

    for (var i = 0; i < 81; i++) {
      if (board[i] == '.') continue;
      final x = step * (i % 9 + 0.5);
      final y = step * (i ~/ 9 + 0.5);
      final center = Offset(x, y);
      final stone = Paint()
        ..color = board[i] == 'B' ? const Color(0xFF2B2B2B) : const Color(0xFFF5F5F5)
        ..style = PaintingStyle.fill;
      canvas.drawCircle(center, step * 0.42, stone);
      if (board[i] == 'W') {
        canvas.drawCircle(
          center,
          step * 0.42,
          Paint()
            ..color = theme.colorScheme.onSurfaceVariant
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1,
        );
      }
      if (i == lastIdx) {
        canvas.drawCircle(
          center,
          step * 0.12,
          Paint()
            ..color = board[i] == 'B' ? Colors.white : Colors.black,
        );
      }
    }
  }

  @override
  bool shouldRepaint(GoPainter oldDelegate) =>
      oldDelegate.board.toString() != board.toString() ||
      oldDelegate.lastIdx != lastIdx;
}

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
      child: InkWell(
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
            _pending[key] = _selected!;
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
    );
  }

  Widget _wtChip(String letter, int index, bool myTurn, ThemeData theme) {
    return InkWell(
      onTap: () {
        if (!myTurn) return;
        setState(() {
          _selected = _selected == '$letter#$index' ? null : '$letter#$index';
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
  }

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
