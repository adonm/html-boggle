/// Home screen: branding, appearance picker, theme menu.
library;

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../audio.dart';
import '../game.dart';
import '../theme.dart';
import 'lobby.dart';
import 'play/boggle.dart';
import 'results.dart';
import 'room.dart';


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
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _MuteButton(),
        IconButton(
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
        ),
      ],
    );
  }
}

/// Mute toggle for the bundled sound effects (persisted).
class _MuteButton extends StatefulWidget {
  @override
  State<_MuteButton> createState() => _MuteButtonState();
}

class _MuteButtonState extends State<_MuteButton> {
  bool _muted = Sfx.muted;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: _muted ? 'Unmute sounds' : 'Mute sounds',
      icon: Icon(_muted ? Icons.volume_off_outlined : Icons.volume_up_outlined),
      onPressed: () => setState(() {
        _muted = !_muted;
        Sfx.setMuted(_muted);
      }),
    );
  }
}

// ------------------------------------------------------------------- lobby

