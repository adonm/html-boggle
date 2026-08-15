/// Screens: lobby, joining, room, play, results. Styled by the Yaru themes
/// with semantics labels so screen readers and tests can navigate the game.
/// Layouts adapt to phone-sized viewports (stacked board, scrollable panels).
library;

import 'package:confetti/confetti.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';

import 'game.dart';
import 'theme.dart';

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
    // Deep links: /?room=code prefills the room field.
    final room = Uri.base.queryParameters['room'];
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
                      ReadyStartControls(game: g, startLabel: 'START ROUND'),
                      const SizedBox(height: 6),
                      OutlinedButton.icon(
                        onPressed: () async {
                          final url = Uri.base
                              .replace(queryParameters: {'room': g.room}, fragment: '')
                              .toString();
                          await Clipboard.setData(ClipboardData(text: url));
                          g.showToast('Link copied - share it!');
                        },
                        icon: const Icon(Icons.link),
                        label: const Text('SHARE LINK'),
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
              g.currentWord.isEmpty
                  ? 'tap tiles to spell a word'
                  : g.currentWord.toUpperCase(),
              textAlign: TextAlign.center,
              style: theme.textTheme.headlineSmall?.copyWith(
                color: g.currentWord.isEmpty
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
                  onPressed: g.currentWord.length >= 3 ? g.submitWord : null,
                  icon: const Icon(Icons.arrow_forward),
                  label: const Text('SUBMIT'),
                ),
                OutlinedButton.icon(
                  onPressed: g.path.isEmpty ? null : g.popTile,
                  icon: const Icon(Icons.arrow_back),
                  label: const Text('UNDO'),
                ),
                OutlinedButton.icon(
                  onPressed: g.path.isEmpty ? null : g.clearPath,
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
    final order = g.path.indexOf(i);
    final selected = order >= 0;
    final letter = g.board.isEmpty ? '' : g.board[i].toUpperCase();
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
            onTap: () => g.tapTile(i),
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
                const SizedBox(height: 18),
                ReadyStartControls(game: g, startLabel: 'NEXT ROUND'),
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
