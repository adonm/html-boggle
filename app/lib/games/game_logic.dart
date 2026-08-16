/// Game logic protocol: the room shell (game.dart) hosts one [GameLogic] at a
/// time. Each game owns its state, builds the fields of the round-start
/// message, handles its own gossip messages, and contributes the fields it
/// wants replicated in host state snapshots (with monotonic adoption, so a
/// stale snapshot can never regress a live round).
///
/// Everything a logic may need from the shell goes through [GameHost], which
/// keeps the logics decoupled and unit-testable with a fake host.
library;

import 'dart:math';

import '../board.dart';
import 'boggle_logic.dart';
import 'chess_logic.dart';
import 'go_logic.dart';
import 'scatter_logic.dart';
import 'sketch_logic.dart';
import 'wt_logic.dart';

enum Phase { lobby, joining, room, play, results }

/// Which game the room is playing (the round starter's choice wins).
enum GameMode { boggle, scattergories, sketchit, chess, go, wordtiles }

extension GameModeInfo on GameMode {
  String get title => switch (this) {
        GameMode.boggle => 'Boggle',
        GameMode.scattergories => 'Scattergories',
        GameMode.sketchit => 'SketchIt',
        GameMode.chess => 'Chess',
        GameMode.go => 'Go (9×9)',
        GameMode.wordtiles => 'Word Tiles',
      };

  String get description => switch (this) {
        GameMode.boggle =>
          'Find words in the 4×4 letter grid before the 3-minute timer runs out. '
              'Words: 3+ letters over adjacent tiles (any direction), each tile once. '
              'Classic scoring (longer = more points).',
        GameMode.scattergories =>
          'Each round deals a random letter. Type words starting with it before time '
              'runs out. At the reveal, duplicates cancel - only unique words score.',
        GameMode.sketchit =>
          'One player draws a secret word on the canvas while everyone guesses from '
              'a letter-count hint (the word is never shown to guessers). Type the '
              'exact answer to score - drawer and guesser both get a point. The '
              'drawer rotates each round.',
        GameMode.chess =>
          'Full chess rules: castling, en passant, promotion with a piece '
              'picker, checkmate, stalemate, threefold repetition. Two players; '
              'everyone else spectates. Solo practice plays both sides.',
        GameMode.go =>
          'Go on a 9×9 board: place stones, capture groups by surrounding them, '
              'simple ko rule. Two consecutive passes end the game; area scoring '
              '(stones + surrounded territory) decides the winner. Two players, '
              'others spectate. Solo practice plays both sides.',
        GameMode.wordtiles =>
          'Scrabble-style crossword: build words from your 7-tile rack onto the '
              'board, connecting to existing letters. Every formed word must be '
              'in the dictionary; the opening play through the center star is '
              'doubled and a 7-tile play earns +50.',
      };

  String get howTo => switch (this) {
        GameMode.boggle =>
          'Tap tiles to spell, ENTER to submit. The host arbitrates duplicates; '
              'first to find a word keeps it.',
        GameMode.scattergories =>
          'Type words into the box and hit enter. Think fast - slowpokes get '
              'canceled by duplicates at the reveal.',
        GameMode.sketchit =>
          'Drawer: draw with your finger/mouse, clear the canvas if you need a '
              'restart. Guessers: type guesses at the answer - an exact match '
              'wins the round.',
        GameMode.chess =>
          'Tap a piece, then a highlighted square to move. Only legal moves are '
              'highlighted; checkmate (not a king capture) ends the game.',
        GameMode.go =>
          'Tap an empty intersection to place a stone. Surround enemy groups to '
              'capture them. PASS when you have nothing useful - two passes in a '
              'row end the game.',
        GameMode.wordtiles =>
          'Tap a rack tile, then an empty square to place it (tap a placed tile '
              'to recall it). PLAY submits - every formed word must be real. '
              'PASS to skip your turn.',
      };

  bool get implemented => true;

  String get wireName => name;
}

GameMode modeFromWire(String? s) => GameMode.values.asNameMap()[s] ?? GameMode.boggle;

/// A player in the room.
class Player {
  Player(this.id, this.name);

  final String id;
  String name;
  int score = 0;
  bool ready = false;
  final Set<String> words = {};
  DateTime lastSeen = DateTime.now();
  bool isMe = false;

  Map<String, dynamic> toJson() => {
        'node': id,
        'name': name,
        'score': score,
        'ready': ready,
        'words': words.toList(),
      };
}

/// What the room shell exposes to a [GameLogic].
abstract class GameHost {
  String get meId;
  String get myName;
  Phase get phase;
  List<Player> get players;
  List<Player> get sortedPlayers;
  bool get isHost;
  Random get rng;
  WordFinder get finder;
  String get room;
  int get round;
  DateTime? get deadline;
  set deadline(DateTime? value);

  void send(Map<String, dynamic> m);
  void showToast(String msg);
  /// Bump the failed-attempt counter (word shake) + haptic.
  void pulseWordAttempt();
  /// Bump the award counter (confetti burst) + haptic.
  void pulseAward();
  /// Add points to a player's running score.
  void addScore(String playerId, int points);
  /// End the round now (deadline to the past; the tick flips to results).
  void endRound();
  void notifyListeners();
}

/// One playable game inside the room shell.
abstract class GameLogic {
  GameLogic(this.host);

  final GameHost host;

  String get wireName;
  bool get isMyTurn => false;
  /// Toast shown when a round starts ("Round N - ...").
  String get startToast => 'Round ${host.round} - find words!';

  /// Round starter: build the game's round state and add its fields to the
  /// start message (may also override [GameHost.deadline]).
  void populateStart(Map<String, dynamic> msg);

  /// Everyone: adopt the game fields of a remote start message.
  void applyStart(Map<String, dynamic> m);

  /// Handle a game-specific gossip message (type != shell types).
  void onMessage(String type, Map<String, dynamic> m, String from);

  /// Fields to include in host state snapshots.
  Map<String, dynamic> stateJson() => const {};

  /// Adopt the game fields of a host state snapshot (monotonically).
  void adoptState(Map<String, dynamic> m) {}

  /// Per-second hook (e.g. claim retries).
  void onTick() {}

  /// Debug/test fields merged into the shell's debug state.
  Map<String, dynamic> debugJson() => const {};

  /// Forget all round state (on leaving the room).
  void reset() {}
}

GameLogic createLogic(GameMode mode, GameHost host) => switch (mode) {
      GameMode.boggle => BoggleLogic(host),
      GameMode.scattergories => ScatterLogic(host),
      GameMode.sketchit => SketchLogic(host),
      GameMode.chess => ChessLogic(host),
      GameMode.go => GoLogic(host),
      GameMode.wordtiles => WtLogic(host),
    };
