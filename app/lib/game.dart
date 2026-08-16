/// The game: state machine, deterministic host, word arbitration and the
/// gossip message protocol (identical to the previous raylib implementation,
/// so any client version interoperates).
library;

import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'board.dart';
import 'chess.dart';
import 'go.dart';
import 'net.dart';
import 'wordtiles.dart';

@JS('window.localStorage')
external JSObject get _storage;

@JS('window')
external JSObject get _window;

enum Phase { lobby, joining, room, play, results }

/// Which game the room is playing (the round starter's choice wins).
enum GameMode { boggle, scattergories, sketchit, chess, go, wordtiles }

extension GameModeInfo on GameMode {
  String get title => switch (this) {
        GameMode.boggle => 'Boggle',
        GameMode.scattergories => 'Scattergories',
        GameMode.sketchit => 'SketchIt',
        GameMode.chess => 'Capture Chess',
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
          'One player draws a secret word on the canvas while everyone guesses. Type '
              'the exact answer to score (drawer and guesser both get a point). The '
              'drawer rotates each round.',
        GameMode.chess =>
          'Chess with a twist: capture the king to win - no check/checkmate '
              'bookkeeping, no castling. Pawns auto-promote to queens. Two players; '
              'everyone else spectates.',
        GameMode.go =>
          'Go on a 9×9 board: place stones, capture groups by surrounding them, '
              'simple ko rule. Two consecutive passes end the game; area scoring '
              '(stones + surrounded territory) decides the winner. Two players, '
              'others spectate.',
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
              'restart. Guessers: type guesses - exact match wins the round.',
        GameMode.chess =>
          'Tap a piece, then a highlighted square to move. Capturing the enemy '
              'king ends the game immediately.',
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

const int roundMs = 180000;
const Duration helloInterval = Duration(seconds: 5);
const Duration stateInterval = Duration(seconds: 10);
const Duration playerTimeout = Duration(seconds: 45);
const Duration leaderTimeout = Duration(seconds: 25);
const Duration pendingRetry = Duration(seconds: 5);

const List<String> randomNames = [
  'Quilt', 'Dicey', 'Zinger', 'Puzzle', 'Bingo', 'Lexi', 'Tango', 'Jumble',
  'Clever', 'Snappy', 'Witty', 'Mango', 'Doodle', 'Fable', 'Pixel', 'Gizmo',
  'Turbo', 'Sunny', 'Rascal', 'Comet', 'Whiz', 'Nimbus', 'Biscuit', 'Echo',
];

/// A room chat message.
class ChatMessage {
  ChatMessage({required this.name, required this.text, required this.fromMe});

  final String name;
  final String text;
  final bool fromMe;
  final DateTime at = DateTime.now();
}

class Game extends ChangeNotifier {
  final NetBridge net = NetBridge.instance;
  final Random _rng = Random();

  WordFinder finder = WordFinder(const []);

  Phase phase = Phase.lobby;
  final List<Player> players = [];
  String meId = '';
  String myName = '';
  String room = '';
  List<String> board = const [];
  final List<int> path = [];
  DateTime? deadline;
  int round = 0;
  String? pendingWord;
  DateTime? pendingSentAt;
  String toast = '';
  DateTime? toastUntil;
  DateTime? lastHello;
  DateTime? lastState;
  final List<ChatMessage> chat = [];
  Timer? _ticker;
  StreamSubscription? _eventsSub;
  int _seq = 0;

  // UI flair triggers (consumed by screens).
  int wordAttempts = 0; // failed submissions -> word shake
  int awardPulse = 0; // accepted words -> confetti burst
  int roundEpoch = 0; // round starts -> tile deal-in animation

  String get currentWord => path.map((i) => board[i]).join();
  String get hostId => players.isEmpty
      ? ''
      : players.map((p) => p.id).reduce((a, b) => a.compareTo(b) < 0 ? a : b);
  bool get isHost => meId.isNotEmpty && meId == hostId;
  Player? get me => players.where((p) => p.id == meId).firstOrNull;
  int get totalScore => players.fold(0, (a, p) => a + p.score);
  bool get allReady => players.isNotEmpty && players.every((p) => p.ready);
  int get readyCount => players.where((p) => p.ready).length;
  String _lastHostId = '';
  bool _syncedFromOthers = false; // adopted state/hello from another player
  DateTime? lastWantStateAt;
  int stateSent = 0;
  int stateReceived = 0;
  final List<String> debugLog = [];

  static const Duration wantStateInterval = Duration(seconds: 2);

  void _log(String what) {
    debugLog.add('${DateTime.now().millisecondsSinceEpoch % 100000} $what');
    if (debugLog.length > 40) debugLog.removeAt(0);
  }

  // Scattergories state (submissions per node id; scoring is local +
  // deterministic: unique words count, duplicates cancel).
  GameMode mode = GameMode.boggle;
  String sgLetter = '';
  final Map<String, List<String>> sgWords = {};
  static const String sgLetters = 'ABCDEFGHIJKLMNOPRSTUVWY'; // no Q, X, Z

  // SketchIt state (strokes are ephemeral; word/drawer resume via state).
  String sketchWord = '';
  String sketchDrawer = '';
  bool sketchSolved = false;
  final List<Map<String, dynamic>> sketchStrokes = [];

  // Capture Chess state (deterministic replay from the move list).
  final List<String> chessMoves = [];
  String chessWinner = '';
  // Seats are pinned at round start (carried in start/state messages) so a
  // late-joining spectator can never steal one and desync the move log.
  String chessWhite = '';
  String chessBlack = '';

  // Go (9x9) state: replicated move log, seats pinned at round start.
  final List<String> goMoves = [];
  String goWinner = '';
  String goBlack = '';
  String goWhite = '';

  // Word Tiles state: replicated move log + the bag order served by the
  // round starter; racks and scores derive deterministically from both.
  final List<dynamic> wtMoves = [];
  List<String> wtBag = [];
  List<String> wtSeats = [];
  String wtWinner = '';

  /// Canonical player order (by node id) - identical on every client, used
  /// for role assignment (chess white/black, sketch drawer rotation).
  List<Player> get sortedPlayers =>
      [...players]..sort((a, b) => a.id.compareTo(b.id));

  void setMode(GameMode m) {
    if (m == mode) return;
    if (phase == Phase.lobby || phase == Phase.room || phase == Phase.results) {
      if (!m.implemented) {
        showToast('${m.title}: coming soon');
        return;
      }
      mode = m;
      notifyListeners();
    }
  }

  /// Duplicate check: did more than one player submit [w]?
  bool sgIsDupe(String w) =>
      sgWords.entries.where((e) => e.value.contains(w)).length > 1;

  /// Scattergories score: unique words only.
  int sgScore(String id) {
    var score = 0;
    for (final w in sgWords[id] ?? const <String>[]) {
      if (!sgIsDupe(w)) score++;
    }
    return score;
  }

  List<String> get sgAllWords =>
      (sgWords.values.expand((l) => l).toSet().toList())..sort();

  void submitScattergories(String raw) {
    final w = raw.trim().toLowerCase();
    if (phase != Phase.play || mode != GameMode.scattergories) return;
    if (w.length < 3) {
      wordAttempts++;
      HapticFeedback.selectionClick();
      showToast('Words need at least 3 letters');
      notifyListeners();
      return;
    }
    if (!w.startsWith(sgLetter.toLowerCase())) {
      wordAttempts++;
      HapticFeedback.selectionClick();
      showToast('Must start with "$sgLetter"');
      notifyListeners();
      return;
    }
    if (!finder.hasWord(w)) {
      wordAttempts++;
      HapticFeedback.selectionClick();
      showToast('"$w" is not in the dictionary');
      notifyListeners();
      return;
    }
    if ((sgWords[meId] ?? const <String>[]).contains(w)) {
      wordAttempts++;
      HapticFeedback.selectionClick();
      showToast('You already submitted "$w"');
      notifyListeners();
      return;
    }
    sgWords.putIfAbsent(meId, () => []).add(w);
    send({'t': 'sgSubmit', 'node': meId, 'name': myName, 'word': w});
    HapticFeedback.selectionClick();
    notifyListeners();
  }

  int remainingMs() {
    final dl = deadline;
    if (dl == null) return 0;
    return max(0, dl.difference(DateTime.now()).inMilliseconds);
  }

  Future<void> init() async {
    final text = await rootBundle.loadString('assets/words.txt');
    finder = WordFinder(
      text.split('\n').where((w) => w.length >= 3 && w.length <= 16).toList()
        ..sort(),
    );
    net.registerEventSink();
    _eventsSub = net.events.listen(_onEvent);
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
    maybeRejoin();
  }

  String randomName() => randomNames[_rng.nextInt(randomNames.length)];

  // --------------------------------------------------------------- joining

  Future<void> join({required String roomCode, required String name}) async {
    if (phase == Phase.joining) return;
    final rm = roomCode.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
    if (rm.isEmpty) {
      showToast('Please enter a room code');
      return;
    }
    final nm = name.trim().isEmpty ? randomName() : name.trim();
    myName = nm;
    room = rm;
    // Placeholder only - the play board always arrives with the start/state
    // messages from whoever starts the round.
    board = generateBoard(_rng);
    finder.board = board;
    phase = Phase.joining;
    notifyListeners();
    try {
      final nodeId = await net.join(room: rm, topicHex: topicHex(rm), name: nm);
      meId = nodeId;
      players
        ..clear()
        ..add(Player(meId, nm)..isMe = true);
      _syncedFromOthers = false;
      lastWantStateAt = null;
      pendingWord = null;
      phase = Phase.room;
      lastHello = null;
      lastState = DateTime.now();
      sendHello();
      _persistRoom();
      showToast('Joined room "$rm"');
    } catch (err, st) {
      phase = Phase.lobby;
      _lastError = '$err\n$st';
      showToast('Join failed: $err');
    }
    notifyListeners();
  }

  // ------------------------------------------------------------- messaging

  void send(Map<String, dynamic> m) {
    // Sequence number: iroh-gossip dedupes by content hash, so byte-identical
    // repeats (periodic hellos, claim retries) would be dropped.
    m['n'] = ++_seq;
    net.send(jsonEncode(m));
  }

  void sendHello() => send({'t': 'hello', 'node': meId, 'name': myName});

  void sendAward(String word, String node) =>
      send({'t': 'award', 'node': node, 'word': word, 'points': scoreForLen(word.length)});

  void sendReject(String word, String node, String reason) =>
      send({'t': 'reject', 'node': node, 'word': word, 'reason': reason});

  /// Broadcast a chat message to the room.
  void sendChat(String text) {
    var t = text.trim();
    if (t.isEmpty || phase == Phase.lobby || phase == Phase.joining) return;
    if (t.length > 200) t = t.substring(0, 200);
    send({'t': 'chat', 'node': meId, 'name': myName, 'text': t});
    chat.add(ChatMessage(name: myName, text: t, fromMe: true));
    _trimChat();
    notifyListeners();
  }

  /// Toggle my ready state (starts require everyone ready).
  void toggleReady() {
    final me = this.me;
    if (me == null || (phase != Phase.room && phase != Phase.results)) return;
    me.ready = !me.ready;
    send({'t': 'ready', 'node': meId, 'ready': me.ready});
    notifyListeners();
  }

  void _trimChat() {
    while (chat.length > 100) {
      chat.removeAt(0);
    }
  }

  void sendClaim(String word) =>
      send({'t': 'claim', 'node': meId, 'word': word, 'name': myName});

  void sendState() {
    // Quarantine: a fresh joiner whose node id makes it the host must first
    // adopt the room's state from someone else, or its pre-sync snapshot
    // (empty players, room phase, future deadline) would regress everyone.
    if (players.length > 1 && !_syncedFromOthers) return;
    stateSent++;
    final ph = switch (phase) {
      Phase.play => 'play',
      Phase.results => 'results',
      _ => 'room',
    };
    send({
      't': 'state',
      'node': meId,
      'phase': ph,
      'deadline': deadline?.millisecondsSinceEpoch ?? 0,
      'round': round,
      'mode': mode.wireName,
      'letter': sgLetter,
      'board': board.join(','),
      'sgWords': {for (final e in sgWords.entries) e.key: e.value},
      'sketchWord': sketchWord,
      'sketchDrawer': sketchDrawer,
      'sketchSolved': sketchSolved,
      'chessMoves': chessMoves,
      'chessWinner': chessWinner,
      'chessWhite': chessWhite,
      'chessBlack': chessBlack,
      'goMoves': goMoves,
      'goWinner': goWinner,
      'goBlack': goBlack,
      'goWhite': goWhite,
      'wtMoves': wtMoves,
      'wtBag': wtBag.join(''),
      'wtSeats': wtSeats,
      'wtWinner': wtWinner,
      'players': players.map((p) => p.toJson()).toList(),
    });
  }

  void startRound() {
    if ((phase != Phase.room && phase != Phase.results) || !allReady) return;
    // Whoever starts the round serves authoritative state from here on.
    _syncedFromOthers = true;
    final needsTwo = mode == GameMode.chess || mode == GameMode.go ||
        mode == GameMode.wordtiles;
    if (needsTwo && players.length < 2) {
      showToast('${mode.title} needs 2 players (others can spectate)');
      return;
    }
    deadline = DateTime.now().add(const Duration(milliseconds: roundMs));
    round++;
    switch (mode) {
      case GameMode.scattergories:
        sgLetter = sgLetters[_rng.nextInt(sgLetters.length)];
        sgWords.clear();
        send({
          't': 'start',
          'node': meId,
          'deadline': deadline!.millisecondsSinceEpoch,
          'round': round,
          'mode': mode.wireName,
          'letter': sgLetter,
        });
      case GameMode.sketchit:
        sketchWord = finder.randomWord(_rng, 4, 9) ?? 'cat';
        sketchDrawer = sortedPlayers[(round - 1) % players.length].id;
        sketchStrokes.clear();
        sketchSolved = false;
        deadline = DateTime.now().add(const Duration(seconds: 90));
        send({
          't': 'start',
          'node': meId,
          'deadline': deadline!.millisecondsSinceEpoch,
          'round': round,
          'mode': mode.wireName,
          'word': sketchWord,
          'drawer': sketchDrawer,
        });
      case GameMode.chess:
        chessMoves.clear();
        chessWinner = '';
        final seats = sortedPlayers;
        chessWhite = seats[0].id;
        chessBlack = seats.length > 1 ? seats[1].id : '';
        deadline = DateTime.now().add(const Duration(hours: 1));
        send({
          't': 'start',
          'node': meId,
          'deadline': deadline!.millisecondsSinceEpoch,
          'round': round,
          'mode': mode.wireName,
          'white': chessWhite,
          'black': chessBlack,
        });
      case GameMode.go:
        goMoves.clear();
        goWinner = '';
        final gseats = sortedPlayers;
        goBlack = gseats[0].id;
        goWhite = gseats.length > 1 ? gseats[1].id : '';
        deadline = DateTime.now().add(const Duration(hours: 1));
        send({
          't': 'start',
          'node': meId,
          'deadline': deadline!.millisecondsSinceEpoch,
          'round': round,
          'mode': mode.wireName,
          'black': goBlack,
          'white': goWhite,
        });
      case GameMode.wordtiles:
        wtMoves.clear();
        wtWinner = '';
        wtSeats = [for (final p in sortedPlayers) p.id];
        wtBag = WtGame.shuffledBag();
        deadline = DateTime.now().add(const Duration(hours: 1));
        send({
          't': 'start',
          'node': meId,
          'deadline': deadline!.millisecondsSinceEpoch,
          'round': round,
          'mode': mode.wireName,
          'bag': wtBag.join(''),
          'seats': wtSeats,
        });
      case GameMode.boggle:
        board = generateBoard(_rng);
        finder.board = board;
        send({
          't': 'start',
          'node': meId,
          'deadline': deadline!.millisecondsSinceEpoch,
          'round': round,
          'mode': mode.wireName,
          'board': board.join(','),
        });
    }
    _applyStart();
    notifyListeners();
  }

  void _applyStart() {
    for (final p in players) {
      p.words.clear();
      p.ready = false;
    }
    path.clear();
    pendingWord = null;
    roundEpoch++;
    phase = Phase.play;
    final label = switch (mode) {
      GameMode.sketchit => 'Round $round - start drawing!',
      GameMode.chess => 'Round $round - white moves first',
      GameMode.go => 'Round $round - black moves first',
      GameMode.wordtiles => 'Round $round - first play covers the star',
      GameMode.scattergories => 'Round $round - words starting with $sgLetter!',
      _ => 'Round $round - find words!',
    };
    showToast(label);
  }

  // ------------------------------------------------------------------ play

  void tapTile(int idx) {
    if (phase != Phase.play) return;
    if (path.isNotEmpty && path.last == idx) {
      path.removeLast();
      notifyListeners();
      return;
    }
    if (path.contains(idx)) return;
    if (path.isNotEmpty) {
      final last = path.last;
      final dr = (last ~/ 4 - idx ~/ 4).abs();
      final dc = (last % 4 - idx % 4).abs();
      if (dr > 1 || dc > 1) return;
    }
    path.add(idx);
    notifyListeners();
  }

  void popTile() {
    if (path.isNotEmpty) {
      path.removeLast();
      notifyListeners();
    }
  }

  void clearPath() {
    if (path.isNotEmpty) {
      path.clear();
      notifyListeners();
    }
  }

  void submitWord() {
    if (phase != Phase.play || path.isEmpty) return;
    final word = currentWord;
    final me = this.me;
    path.clear();
    if (me == null) return;
    if (word.length < 3) {
      wordAttempts++;
      HapticFeedback.selectionClick();
      showToast('Words need at least 3 letters');
      notifyListeners();
      return;
    }
    if (me.words.contains(word)) {
      wordAttempts++;
      HapticFeedback.selectionClick();
      showToast('You already found "$word"');
      notifyListeners();
      return;
    }
    if (players.any((p) => p.id != meId && p.words.contains(word))) {
      wordAttempts++;
      HapticFeedback.selectionClick();
      showToast('"$word" is already taken');
      notifyListeners();
      return;
    }
    if (!finder.hasWord(word)) {
      wordAttempts++;
      HapticFeedback.selectionClick();
      showToast('"$word" is not in the dictionary');
      notifyListeners();
      return;
    }
    if (!finder.forms(word)) {
      wordAttempts++;
      HapticFeedback.selectionClick();
      showToast('"$word" is not on the board');
      notifyListeners();
      return;
    }
    if (isHost) {
      me.words.add(word);
      me.score += scoreForLen(word.length);
      sendAward(word, meId);
      awardPulse++;
      HapticFeedback.mediumImpact();
      showToast('+${scoreForLen(word.length)} for "$word"!');
    } else {
      // optimistic: host arbitrates; retried until acknowledged
      me.words.add(word);
      me.score += scoreForLen(word.length);
      pendingWord = word;
      pendingSentAt = DateTime.now();
      sendClaim(word);
      HapticFeedback.selectionClick();
      showToast('Submitted "$word"');
    }
    notifyListeners();
  }

  // ---------------------------------------------------------------- events

  void _onEvent(Map<String, dynamic> evt) {
    final kind = evt['kind'];
    if (kind == 'up') {
      final node = evt['node'] as String?;
      if (node != null && node != meId) {
        if (!players.any((p) => p.id == node)) {
          players.add(Player(node, ''));
          if (isHost) sendState();
        }
        sendHello();
      }
    } else if (kind == 'down') {
      final node = evt['node'] as String?;
      if (node != null && node != meId) {
        _removePlayer(node);
      }
    } else if (kind == 'lagged') {
      showToast('Network hiccup - some messages may be missing');
    } else {
      // App messages arrive bare (glue emits the parsed payload directly:
      // it carries "t"/"node"/... but no "kind").
      _handleMsg(evt);
    }
    notifyListeners();
  }

  void _removePlayer(String node) {
    final p = players.where((p) => p.id == node).firstOrNull;
    players.removeWhere((p) => p.id == node);
    if (p != null) {
      showToast('${p.name.isEmpty ? 'A player' : p.name} left');
      if (isHost) sendState();
    }
  }

  void _handleMsg(Map<String, dynamic> m) {
    final t = m['t'] as String?;
    final node = (m['node'] as String?) ?? '';
    switch (t) {
      case 'hello':
        if (node.isEmpty || node == meId) return;
        final p = players.where((p) => p.id == node).firstOrNull;
        final name = (m['name'] as String?) ?? '';
        if (p == null) {
          players.add(Player(node, name));
          // Any player who knows the room answers a newcomer with a state
          // snapshot (the host may have just changed hands to the newcomer).
          if (_syncedFromOthers) sendState();
        } else {
          if (name.isNotEmpty) p.name = name;
          p.lastSeen = DateTime.now();
        }
      case 'bye':
        _removePlayer(node);
      case 'start':
        // a start message is itself an authoritative round sync
        _syncedFromOthers = true;
        final dl = m['deadline'];
        if (dl is num) {
          deadline = DateTime.fromMillisecondsSinceEpoch(dl.toInt());
        }
        final r = m['round'];
        if (r is num) round = r.toInt();
        mode = modeFromWire(m['mode'] as String?);
        if (mode == GameMode.scattergories) {
          sgLetter = (m['letter'] as String?) ?? '';
          sgWords.clear();
        } else if (mode == GameMode.sketchit) {
          sketchWord = (m['word'] as String?) ?? '';
          sketchDrawer = (m['drawer'] as String?) ?? '';
          sketchStrokes.clear();
          sketchSolved = false;
        } else if (mode == GameMode.chess) {
          chessMoves.clear();
          chessWinner = '';
          chessWhite = (m['white'] as String?) ?? '';
          chessBlack = (m['black'] as String?) ?? '';
        } else if (mode == GameMode.go) {
          goMoves.clear();
          goWinner = '';
          goBlack = (m['black'] as String?) ?? '';
          goWhite = (m['white'] as String?) ?? '';
        } else if (mode == GameMode.wordtiles) {
          wtMoves.clear();
          wtWinner = '';
          final bag = (m['bag'] as String?) ?? '';
          if (bag.isNotEmpty) wtBag = bag.split('');
          final seats = m['seats'];
          if (seats is List) {
            wtSeats = [for (final s in seats) if (s is String) s];
          }
        } else {
          _adoptBoard(m);
        }
        _applyStart();
      case 'claim':
        if (!isHost) return;
        final word = ((m['word'] as String?) ?? '').toLowerCase();
        final p = players.where((p) => p.id == node).firstOrNull;
        if (p == null || phase != Phase.play) return;
        if (word.length < 3 || word.length > 16) {
          sendReject(word, node, 'invalid');
          return;
        }
        if (p.words.contains(word)) {
          sendAward(word, node); // idempotent re-ack: the award was lost
          return;
        }
        if (players.any((q) => q.id != node && q.words.contains(word))) {
          sendReject(word, node, 'taken');
          return;
        }
        if (!finder.hasWord(word) || !finder.forms(word)) {
          sendReject(word, node, 'invalid');
          return;
        }
        p.words.add(word);
        p.score += scoreForLen(word.length);
        sendAward(word, node);
        showToast('${p.name.isEmpty ? 'Someone' : p.name} found "$word"');
      case 'award':
        final word = ((m['word'] as String?) ?? '').toLowerCase();
        final p = players.where((p) => p.id == node).firstOrNull;
        if (p == null || phase != Phase.play) return;
        if (p.words.contains(word)) {
          if (p.isMe && pendingWord == word) pendingWord = null;
          return;
        }
        p.words.add(word);
        p.score += scoreForLen(word.length);
        if (p.isMe && pendingWord == word) pendingWord = null;
        awardPulse++;
        HapticFeedback.mediumImpact();
        if (!p.isMe) {
          showToast('${p.name.isEmpty ? 'Someone' : p.name}: "$word" +${scoreForLen(word.length)}');
        }
      case 'reject':
        if (node != meId) return;
        final word = ((m['word'] as String?) ?? '').toLowerCase();
        if (pendingWord == word) pendingWord = null;
        me?.words.remove(word);
        showToast('"$word" rejected: ${m['reason'] ?? 'no'}');
      case 'chat':
        final text = ((m['text'] as String?) ?? '').trim();
        if (text.isEmpty || node == meId) return;
        chat.add(ChatMessage(
          name: (m['name'] as String?) ?? '',
          text: text,
          fromMe: false,
        ));
        _trimChat();
      case 'sgSubmit':
        if (phase != Phase.play || mode != GameMode.scattergories) return;
        final w = ((m['word'] as String?) ?? '').trim().toLowerCase();
        if (w.length < 3 || !w.startsWith(sgLetter.toLowerCase())) return;
        if (!finder.hasWord(w)) return;
        final list = sgWords.putIfAbsent(node, () => []);
        if (!list.contains(w)) {
          list.add(w);
        }
      case 'sketchStroke':
        if (phase != Phase.play || mode != GameMode.sketchit) return;
        if (node != sketchDrawer) return;
        final stroke = m['stroke'];
        if (stroke is Map) {
          final s = stroke.cast<String, dynamic>();
          final id = s['id'];
          final pts = s['pts'];
          if (id is String && pts is List) {
            final existing =
                sketchStrokes.where((x) => x['id'] == id).firstOrNull;
            if (existing != null) {
              (existing['pts'] as List).addAll(pts);
            } else {
              sketchStrokes.add(s);
            }
            if (sketchStrokes.length > 500) sketchStrokes.removeAt(0);
          }
        }
      case 'sketchClear':
        if (phase != Phase.play || mode != GameMode.sketchit) return;
        if (node != sketchDrawer) return;
        sketchStrokes.clear();
      case 'sketchGuess':
        if (phase != Phase.play || mode != GameMode.sketchit) return;
        if (node == sketchDrawer || sketchSolved) return;
        final guess = ((m['text'] as String?) ?? '').trim().toLowerCase();
        if (guess != sketchWord.toLowerCase()) return;
        if (!isHost) return; // the leader arbitrates the win
        sketchSolved = true;
        final drawer = players.where((p) => p.id == sketchDrawer).firstOrNull;
        final guesser = players.where((p) => p.id == node).firstOrNull;
        drawer?.score++;
        guesser?.score++;
        deadline = DateTime.now().subtract(const Duration(seconds: 1));
        send({
          't': 'sketchSolved',
          'node': meId,
          'word': sketchWord,
          'drawer': sketchDrawer,
          'guesser': node,
        });
        showToast('${guesser?.name ?? 'Someone'} guessed "${sketchWord}"!');
      case 'sketchSolved':
        if (mode != GameMode.sketchit) return;
        sketchSolved = true;
        sketchWord = (m['word'] as String?) ?? sketchWord;
        if (!isHost) {
          final drawer = players.where((p) => p.id == (m['drawer'] as String?)).firstOrNull;
          final guesser = players.where((p) => p.id == (m['guesser'] as String?)).firstOrNull;
          drawer?.score++;
          guesser?.score++;
        }
        deadline = DateTime.now().subtract(const Duration(seconds: 1));
      case 'chessMove':
        if (phase != Phase.play || mode != GameMode.chess) return;
        _applyChessMove(m, node);
      case 'goMove':
        if (phase != Phase.play || mode != GameMode.go) return;
        _applyGoMove(m, node);
      case 'goPass':
        if (phase != Phase.play || mode != GameMode.go) return;
        _applyGoPass(node);
      case 'goResign':
        if (phase != Phase.play || mode != GameMode.go) return;
        if (node != goBlack && node != goWhite) return;
        goWinner = node == goBlack ? 'white' : 'black';
        _endGo();
      case 'wtMove':
        if (phase != Phase.play || mode != GameMode.wordtiles) return;
        _applyWtMove(m, node);
      case 'wtPass':
        if (phase != Phase.play || mode != GameMode.wordtiles) return;
        _applyWtPass(node);
      case 'ready':
        final p = players.where((p) => p.id == node).firstOrNull;
        if (p != null && m['ready'] is bool) {
          p.ready = m['ready'] as bool;
        }
      case 'state':
        _applyState(m);
      case 'wantState':
        // A newcomer asks for a snapshot; any synced player answers.
        if (_syncedFromOthers) sendState();
    }
  }

  void _applyState(Map<String, dynamic> m) {
    _syncedFromOthers = true;
    stateReceived++;
    // Never regress the players list from a peer's state that doesn't even
    // contain that peer's own... note: adopt players only from a state that
    // is at least as far along as ours (phase-monotonic) - see below.
    final ph = m['phase'];
    final incomingPhase = ph == 'play'
        ? Phase.play
        : ph == 'results'
            ? Phase.results
            : Phase.room;
    final phaseRank = (Phase p) => switch (p) {
          Phase.room => 0,
          Phase.play => 1,
          Phase.results => 2,
          _ => 0,
        };
    final adopt = phaseRank(incomingPhase) >= phaseRank(phase);
    _log('state from ${m['node']} ph=$ph adopt=$adopt local=${phase.name}');
    if (adopt) {
      final list = m['players'];
      if (list is List) {
        players.clear();
        for (final item in list) {
          if (item is! Map) continue;
          final id = item['node'] as String?;
          if (id == null) continue;
          final p = Player(id, (item['name'] as String?) ?? '');
          p.score = (item['score'] as num?)?.toInt() ?? 0;
          p.ready = item['ready'] == true;
          final words = item['words'];
          if (words is List) {
            for (final w in words) {
              if (w is String) p.words.add(w);
            }
          }
          p.isMe = id == meId;
          p.lastSeen = DateTime.now();
          players.add(p);
        }
        if (!players.any((p) => p.id == meId)) {
          players.add(Player(meId, myName)..isMe = true);
        }
      }
      if (incomingPhase == Phase.play) {
        phase = Phase.play;
        path.clear();
      } else if (incomingPhase == Phase.results) {
        phase = Phase.results;
      } else {
        phase = Phase.room;
      }
      final dl = m['deadline'];
      if (dl is num) {
        deadline = DateTime.fromMillisecondsSinceEpoch(dl.toInt());
      }
    }
    final r = m['round'];
    if (r is num) round = r.toInt();
    mode = modeFromWire(m['mode'] as String?);
    final letter = m['letter'];
    if (letter is String && letter.isNotEmpty) sgLetter = letter;
    final sg = m['sgWords'];
    if (sg is Map) {
      sgWords.clear();
      for (final e in sg.entries) {
        if (e.key is String && e.value is List) {
          sgWords[e.key as String] = [
            for (final w in (e.value as List)) if (w is String) w,
          ];
        }
      }
    }
    final sw = m['sketchWord'];
    if (sw is String && sw.isNotEmpty) sketchWord = sw;
    final sd = m['sketchDrawer'];
    if (sd is String && sd.isNotEmpty) sketchDrawer = sd;
    // solved/winner are sticky within a round (start resets them) so a stale
    // host snapshot can't regress them either.
    sketchSolved = sketchSolved || m['sketchSolved'] == true;
    final cm = m['chessMoves'];
    if (cm is List) {
      // The move log is append-only: a freshly elected host (e.g. a just-
      // joined spectator with the smallest node id) may broadcast a stale
      // snapshot; never truncate the local log - keep the longer one.
      final incoming = [for (final v in cm) if (v is String) v];
      if (incoming.length >= chessMoves.length) {
        chessMoves
          ..clear()
          ..addAll(incoming);
      }
    }
    final cw = m['chessWinner'];
    if (cw is String && cw.isNotEmpty && chessWinner.isEmpty) chessWinner = cw;
    final cwt = m['chessWhite'];
    if (cwt is String && cwt.isNotEmpty) chessWhite = cwt;
    final cbt = m['chessBlack'];
    if (cbt is String && cbt.isNotEmpty) chessBlack = cbt;
    final gm = m['goMoves'];
    if (gm is List) {
      final incoming = [for (final v in gm) if (v is String) v];
      if (incoming.length >= goMoves.length) {
        goMoves
          ..clear()
          ..addAll(incoming);
      }
    }
    final gw = m['goWinner'];
    if (gw is String && gw.isNotEmpty && goWinner.isEmpty) goWinner = gw;
    final gb = m['goBlack'];
    if (gb is String && gb.isNotEmpty) goBlack = gb;
    final gwt = m['goWhite'];
    if (gwt is String && gwt.isNotEmpty) goWhite = gwt;
    final wm = m['wtMoves'];
    if (wm is List && wm.length >= wtMoves.length) {
      wtMoves
        ..clear()
        ..addAll(wm);
    }
    final wb = m['wtBag'];
    if (wb is String && wb.isNotEmpty) wtBag = wb.split('');
    final wseats = m['wtSeats'];
    if (wseats is List && wseats.isNotEmpty) {
      wtSeats = [for (final s in wseats) if (s is String) s];
    }
    final ww = m['wtWinner'];
    if (ww is String && ww.isNotEmpty && wtWinner.isEmpty) wtWinner = ww;
    if (phase == Phase.play) {
      // mid-round sync: adopt the served board so everyone agrees
      _adoptBoard(m);
    }
  }

  /// Adopt the board served by the round starter (start/state messages).
  /// Falls back to the deterministic derivation if the message has none.
  void _adoptBoard(Map<String, dynamic> m) {
    final b = m['board'];
    if (b is String) {
      final tiles = b.split(',');
      if (tiles.length == 16 && tiles.every((t) => t.isNotEmpty)) {
        board = tiles;
        finder.board = board;
        return;
      }
    }
    board = deriveBoard(room, round);
    finder.board = board;
  }

  // ------------------------------------------------------------------ tick

  void _tick() {
    final now = DateTime.now();
    if (phase == Phase.room || phase == Phase.play || phase == Phase.results) {
      if (lastHello == null || now.difference(lastHello!) >= helloInterval) {
        lastHello = now;
        sendHello();
      }
      // An unsynced joiner keeps asking for a state snapshot until someone
      // answers - gossip links can be transiently one-way, so one-shot
      // hello replies are not enough.
      if (!_syncedFromOthers &&
          players.length > 1 &&
          (lastWantStateAt == null ||
              now.difference(lastWantStateAt!) >= wantStateInterval)) {
        lastWantStateAt = now;
        send({'t': 'wantState', 'node': meId});
      }
      if (phase == Phase.play &&
          isHost &&
          (lastState == null || now.difference(lastState!) >= stateInterval)) {
        lastState = now;
        sendState();
      }
      if (phase == Phase.play && pendingWord != null && !isHost &&
          (pendingSentAt == null || now.difference(pendingSentAt!) >= pendingRetry)) {
        pendingSentAt = now;
        sendClaim(pendingWord!);
      }
      final before = players.length;
      players.removeWhere((p) => !p.isMe && now.difference(p.lastSeen) > playerTimeout);
      if (players.length != before && isHost) sendState();
      // Self-healing leadership: if the leader goes silent for a while,
      // drop it so the next smallest node id takes over.
      final host = hostId;
      if (host.isNotEmpty && host != meId) {
        final hp = players.where((p) => p.id == host).firstOrNull;
        if (hp != null && now.difference(hp.lastSeen) > leaderTimeout) {
          showToast('${hp.name.isEmpty ? 'The leader' : hp.name} went away - reselecting');
          players.removeWhere((p) => p.id == host);
        }
      }
      // Announce leadership changes: the new leader re-syncs everyone.
      if (hostId != _lastHostId) {
        _lastHostId = hostId;
        if (isHost) {
          showToast('You are the leader now');
          sendState();
        }
      }
      if (phase == Phase.play && deadline != null && now.isAfter(deadline!)) {
        phase = Phase.results;
        HapticFeedback.heavyImpact();
        showToast('Round over!');
        if (isHost) sendState();
      }
    }
    if (toastUntil != null && now.isAfter(toastUntil!)) {
      toast = '';
    }
    notifyListeners();
  }

  void showToast(String msg) {
    toast = msg;
    toastUntil = DateTime.now().add(const Duration(milliseconds: 2600));
  }

  // ---------------------------------------------------------------- debug

  /// Test/debug hook: submit a word as if tapped out and confirmed.
  void debugSubmit(String word) {
    if (phase != Phase.play) return;
    final p = finder.findPath(word.toLowerCase());
    if (p == null) return;
    path
      ..clear()
      ..addAll(p);
    submitWord();
  }

  /// Test/debug helper: end the current round immediately.
  void debugEndRound() {
    if (phase == Phase.play) {
      deadline = DateTime.now().subtract(const Duration(seconds: 1));
    }
  }

  /// Test/debug helper: force the room's game mode.
  void debugSetMode(String wireName) {
    mode = modeFromWire(wireName);
    notifyListeners();
  }

  // ----------------------------------------------------------------- sketch

  /// Drawer: append a stroke or a delta of points (canvas coords 0..1).
  /// A new stroke sends [id] + start point; later deltas reuse the id and
  /// only carry the new points so the wire stays light while drawing.
  void sketchDraw(double color, double width, List<double> pts,
      {String? id}) {
    if (phase != Phase.play || mode != GameMode.sketchit) return;
    if (meId != sketchDrawer) return;
    if (id == null) {
      sketchStrokes.add({'color': color, 'width': width, 'pts': pts});
      if (sketchStrokes.length > 500) sketchStrokes.removeAt(0);
      send({
        't': 'sketchStroke',
        'node': meId,
        'stroke': {'color': color, 'width': width, 'pts': pts},
      });
      return;
    }
    final existing = sketchStrokes.where((x) => x['id'] == id).firstOrNull;
    if (existing != null) {
      (existing['pts'] as List).addAll(pts);
    } else {
      sketchStrokes.add({'id': id, 'color': color, 'width': width, 'pts': pts});
    }
    send({
      't': 'sketchStroke',
      'node': meId,
      'stroke': {'id': id, 'color': color, 'width': width, 'pts': pts},
    });
  }

  /// Drawer: clear the canvas.
  void sketchClearCanvas() {
    if (phase != Phase.play || mode != GameMode.sketchit) return;
    if (meId != sketchDrawer) return;
    sketchStrokes.clear();
    send({'t': 'sketchClear', 'node': meId});
  }

  /// Guesser: send a guess.
  void sketchGuess(String text) {
    if (phase != Phase.play || mode != GameMode.sketchit) return;
    if (meId == sketchDrawer || sketchSolved) return;
    send({'t': 'sketchGuess', 'node': meId, 'name': myName, 'text': text.trim()});
  }

  // ----------------------------------------------------------------- chess

  bool get chessWhiteTurn => chessMoves.length.isEven;
  String get chessTurnId =>
      chessWhiteTurn ? chessWhite : chessBlack;

  /// Current player: attempt a move from-to ("e2", "e4").
  bool chessTryMove(String from, String to) {
    if (phase != Phase.play || mode != GameMode.chess) return false;
    if (chessWinner.isNotEmpty) return false;
    if (meId != chessTurnId) return false;
    final f = ChessBoard.sq(from);
    final t = ChessBoard.sq(to);
    if (f < 0 || t < 0 || f == t) return false;
    final b = ChessBoard.fromMoves(chessMoves);
    if (!ChessBoard.targets(b, f).contains(t)) return false;
    final move = '${from}${to}';
    chessMoves.add(move);
    send({'t': 'chessMove', 'node': meId, 'from': from, 'to': to});
    _checkChessEnd(b);
    notifyListeners();
    return true;
  }

  void _applyChessMove(Map<String, dynamic> m, String node) {
    if (chessWinner.isNotEmpty) return;
    if (node != chessTurnId) return;
    final f = ChessBoard.sq((m['from'] as String?) ?? '');
    final t = ChessBoard.sq((m['to'] as String?) ?? '');
    if (f < 0 || t < 0 || f == t) return;
    final b = ChessBoard.fromMoves(chessMoves);
    if (!ChessBoard.targets(b, f).contains(t)) return;
    chessMoves.add('${m['from']}${m['to']}');
    _checkChessEnd(b);
    notifyListeners();
  }

  void _checkChessEnd(List<String> before) {
    // A capture is simply the king disappearing from the board.
    final after = ChessBoard.fromMoves(chessMoves);
    if (before.contains('k') && !after.contains('k')) {
      chessWinner = 'white';
      players.where((p) => p.id == chessWhite).firstOrNull?.score++;
      deadline = DateTime.now().subtract(const Duration(seconds: 1));
      showToast('White captures the king - white wins!');
      return;
    }
    if (before.contains('K') && !after.contains('K')) {
      chessWinner = 'black';
      players.where((p) => p.id == chessBlack).firstOrNull?.score++;
      deadline = DateTime.now().subtract(const Duration(seconds: 1));
      showToast('Black captures the king - black wins!');
    }
  }

  // -------------------------------------------------------------------- go

  bool get goBlackTurn => goMoves.length.isEven; // black moves first
  String get goTurnId => goBlackTurn ? goBlack : goWhite;

  /// Current player: place a stone at a coordinate ("b3").
  bool goTryMove(String coord) {
    if (phase != Phase.play || mode != GameMode.go) return false;
    if (goWinner.isNotEmpty || meId != goTurnId) return false;
    final r = GoGame.replay(goMoves);
    final idx = GoGame.sq(coord);
    if (GoGame.apply(r.board, r.prev, idx, goBlackTurn) == null) {
      showToast('illegal move');
      return false;
    }
    goMoves.add(coord);
    send({'t': 'goMove', 'node': meId, 'coord': coord});
    notifyListeners();
    return true;
  }

  void goPassTurn() {
    if (phase != Phase.play || mode != GameMode.go) return;
    if (goWinner.isNotEmpty || meId != goTurnId) return;
    goMoves.add('pass');
    send({'t': 'goPass', 'node': meId});
    _checkGoEnd();
    notifyListeners();
  }

  void goResign() {
    if (phase != Phase.play || mode != GameMode.go) return;
    if (meId != goBlack && meId != goWhite) return;
    goWinner = meId == goBlack ? 'white' : 'black';
    send({'t': 'goResign', 'node': meId});
    _endGo();
    notifyListeners();
  }

  void _applyGoMove(Map<String, dynamic> m, String node) {
    if (goWinner.isNotEmpty || node != goTurnId) return;
    final r = GoGame.replay(goMoves);
    final idx = GoGame.sq((m['coord'] as String?) ?? '');
    if (GoGame.apply(r.board, r.prev, idx, goBlackTurn) == null) return;
    goMoves.add((m['coord'] as String?) ?? '');
    notifyListeners();
  }

  void _applyGoPass(String node) {
    if (goWinner.isNotEmpty || node != goTurnId) return;
    goMoves.add('pass');
    _checkGoEnd();
    notifyListeners();
  }

  /// Two consecutive passes end the game; area scoring decides.
  void _checkGoEnd() {
    if (goWinner.isNotEmpty) return;
    if (goMoves.length < 2) return;
    if (goMoves[goMoves.length - 1] == 'pass' &&
        goMoves[goMoves.length - 2] == 'pass') {
      final r = GoGame.replay(goMoves);
      final s = GoGame.score(r.board);
      goWinner = s.black == s.white
          ? 'draw'
          : (s.black > s.white ? 'black' : 'white');
      _endGo();
    }
  }

  void _endGo() {
    final winnerId = switch (goWinner) {
      'black' => goBlack,
      'white' => goWhite,
      _ => '',
    };
    players.where((p) => p.id == winnerId).firstOrNull?.score++;
    deadline = DateTime.now().subtract(const Duration(seconds: 1));
    showToast('Game over!');
  }

  // ------------------------------------------------------------- word tiles

  String get wtTurnId =>
      wtSeats.isEmpty ? '' : wtSeats[wtMoves.length % wtSeats.length];

  /// Derived board: {x:y -> letter} from the replicated move log.
  Map<String, String> get wtBoard => WtGame.boardFromMoves(wtMoves);

  /// Derived rack for a seat: initial 7 in seat order, refill to 7 after
  /// each of that seat's moves. Deterministic from bag + move log.
  List<String> wtRackOf(int seatIdx) {
    if (wtBag.isEmpty) return const [];
    var bagIdx = 0;
    final racks = List.generate(wtSeats.length, (_) => <String>[]);
    for (var i = 0; i < wtSeats.length; i++) {
      final n = wtBag.length - bagIdx;
      final take = n < 7 ? n : 7;
      racks[i].addAll(wtBag.sublist(bagIdx, bagIdx + take));
      bagIdx += take;
    }
    for (var t = 0; t < wtMoves.length; t++) {
      final seat = t % wtSeats.length;
      final mv = wtMoves[t];
      if (mv is List) {
        for (final tile in mv) {
          racks[seat].remove((tile[2] as String).toUpperCase());
        }
        while (racks[seat].length < 7 && bagIdx < wtBag.length) {
          racks[seat].add(wtBag[bagIdx++]);
        }
      }
    }
    return racks[seatIdx];
  }

  List<String> get wtMyRack {
    final i = wtSeats.indexOf(meId);
    return i < 0 ? const [] : wtRackOf(i);
  }

  /// Derived score for a seat: replay the log, scoring each play.
  int wtScoreOf(int seatIdx) {
    var score = 0;
    var board = <String, String>{};
    for (var t = 0; t < wtMoves.length; t++) {
      final mv = wtMoves[t];
      if (mv is! List) continue;
      final seat = t % wtSeats.length;
      final tiles = <List<dynamic>>[
        for (final tile in mv)
          [
            (tile[0] as num).toInt(),
            (tile[1] as num).toInt(),
            (tile[2] as String).toUpperCase(),
          ],
      ];
      final opening = board.isEmpty;
      final words = WtGame.formedWords(board, tiles);
      if (seat == seatIdx) {
        score += WtGame.scoreWords(
          words,
          opening: opening,
          tileCount: tiles.length,
        );
      }
      for (final t in tiles) {
        board['${t[0]}:${t[1]}'] = t[2] as String;
      }
    }
    return score;
  }

  int get wtMyScore {
    final i = wtSeats.indexOf(meId);
    return i < 0 ? 0 : wtScoreOf(i);
  }

  /// Current player: play tiles [[x, y, letter], ...].
  bool wtTryPlay(List<List<dynamic>> tiles) {
    if (phase != Phase.play || mode != GameMode.wordtiles) return false;
    if (wtWinner.isNotEmpty || meId != wtTurnId) return false;
    final err = WtGame.validate(
      board: wtBoard,
      rack: wtMyRack,
      tiles: tiles,
      hasWord: finder.hasWord,
    );
    if (err != null) {
      showToast(err);
      return false;
    }
    final wire = [
      for (final t in tiles)
        [(t[0] as num).toInt(), (t[1] as num).toInt(), (t[2] as String).toUpperCase()],
    ];
    wtMoves.add(wire);
    send({'t': 'wtMove', 'node': meId, 'tiles': wire});
    _checkWtEnd();
    notifyListeners();
    return true;
  }

  void wtPassTurn() {
    if (phase != Phase.play || mode != GameMode.wordtiles) return;
    if (wtWinner.isNotEmpty || meId != wtTurnId) return;
    wtMoves.add('pass');
    send({'t': 'wtPass', 'node': meId});
    _checkWtEnd();
    notifyListeners();
  }

  void _applyWtMove(Map<String, dynamic> m, String node) {
    if (wtWinner.isNotEmpty || node != wtTurnId) return;
    final raw = m['tiles'];
    if (raw is! List) return;
    final tiles = <List<dynamic>>[];
    for (final t in raw) {
      if (t is! List || t.length < 3) return;
      if (t[0] is! num || t[1] is! num || t[2] is! String) return;
      tiles.add([(t[0] as num).toInt(), (t[1] as num).toInt(), t[2]]);
    }
    final err = WtGame.validate(
      board: wtBoard,
      rack: wtRackOf(wtSeats.indexOf(node)),
      tiles: tiles,
      hasWord: finder.hasWord,
    );
    if (err != null) return;
    wtMoves.add(tiles);
    _checkWtEnd();
    notifyListeners();
  }

  void _applyWtPass(String node) {
    if (wtWinner.isNotEmpty || node != wtTurnId) return;
    wtMoves.add('pass');
    _checkWtEnd();
    notifyListeners();
  }

  /// End when the bag is empty and a rack empties, or everyone passes in a
  /// row. Highest score wins.
  void _checkWtEnd() {
    if (wtWinner.isNotEmpty) return;
    // remaining bag size: initial 7 per seat, then refills as moves consume
    var remaining = wtBag.length;
    for (var i = 0; i < wtSeats.length; i++) {
      remaining = remaining > 7 ? remaining - 7 : 0;
    }
    for (var t = 0; t < wtMoves.length; t++) {
      if (wtMoves[t] is! List || remaining <= 0) continue;
      final seat = t % wtSeats.length;
      var rack = wtRackOf(seat).length;
      while (rack < 7 && remaining > 0) {
        remaining--;
        rack++;
      }
    }
    final bagEmpty = remaining <= 0;
    var rackEmpty = false;
    for (var i = 0; i < wtSeats.length; i++) {
      if (wtRackOf(i).isEmpty) rackEmpty = true;
    }
    final allPassed = wtMoves.length >= wtSeats.length &&
        wtMoves
            .sublist(wtMoves.length - wtSeats.length)
            .every((m) => m == 'pass');
    if (!((bagEmpty && rackEmpty) || allPassed)) return;
    var best = -1;
    var bestSeat = -1;
    var tie = false;
    for (var i = 0; i < wtSeats.length; i++) {
      final s = wtScoreOf(i);
      if (s > best) {
        best = s;
        bestSeat = i;
        tie = false;
      } else if (s == best) {
        tie = true;
      }
    }
    wtWinner = tie ? 'draw' : wtSeats[bestSeat];
    players.where((p) => p.id == wtWinner).firstOrNull?.score++;
    deadline = DateTime.now().subtract(const Duration(seconds: 1));
    showToast('Game over!');
  }

  // ------------------------------------------------------- room persistence

  /// Rejoin the last room on startup (identity persists via the stored iroh
  /// secret key; game state resyncs from the host snapshots).
  void maybeRejoin() {
    if (phase != Phase.lobby) return;
    final storedRoom = _storageGet('boggle.room');
    if (storedRoom == null || storedRoom.isEmpty) return;
    final storedName = _storageGet('boggle.name') ?? '';
    Future.delayed(const Duration(milliseconds: 800), () {
      if (phase == Phase.lobby) {
        showToast('Rejoining room $storedRoom');
        join(roomCode: storedRoom, name: storedName);
      }
    });
  }

  /// Leave the current room and forget it locally.
  void leaveRoom() {
    if (phase == Phase.lobby || phase == Phase.joining) return;
    send({'t': 'bye', 'node': meId});
    _storageRemove('boggle.room');
    players.clear();
    chat.clear();
    sgWords.clear();
    sketchStrokes.clear();
    chessMoves.clear();
    goMoves.clear();
    wtMoves.clear();
    path.clear();
    pendingWord = null;
    _lastHostId = '';
    _syncedFromOthers = false;
    phase = Phase.lobby;
    showToast('Left the room');
    notifyListeners();
  }

  static String? _storageGet(String key) {
    try {
      final raw = _storage.callMethod<JSAny?>('getItem'.toJS, key.toJS);
      if (raw != null && !raw.isUndefinedOrNull) return (raw as JSString).toDart;
    } catch (_) {
      /* storage unavailable */
    }
    return null;
  }

  /// Debug: raw per-type receive counters from the glue layer.
  static String _glueStats() {
    try {
      final f = _window.getProperty<JSObject?>('__boggleGlueStats'.toJS);
      if (f == null) return '';
      final raw = f.callMethod<JSAny?>('call'.toJS, f);
      if (raw is JSString) return raw.toDart;
    } catch (_) {
      /* not available */
    }
    return '';
  }

  static void _storageRemove(String key) {
    try {
      _storage.callMethod<JSAny?>('removeItem'.toJS, key.toJS);
    } catch (_) {
      /* storage unavailable */
    }
  }

  void _persistRoom() {
    try {
      _storage.callMethod<JSAny?>('setItem'.toJS, 'boggle.room'.toJS, room.toJS);
      _storage.callMethod<JSAny?>('setItem'.toJS, 'boggle.name'.toJS, myName.toJS);
    } catch (_) {
      /* storage unavailable */
    }
  }

  Map<String, dynamic> debugState() => {
        'phase': phase.name,
        'players': players.length,
        'room': room,
        'me': meId,
        'total': totalScore,
        'words': me?.words.length ?? 0,
        'cur': currentWord,
        'toast': toast,
        'error': _lastError,
        'mode': mode.name,
        'letter': sgLetter,
        'board': board.join(','),
        'sgCount': sgWords[meId]?.length ?? 0,
        'sgScore': sgScore(meId),
        'sgScores': {for (final id in sgWords.keys) id: sgScore(id)},
        'sgAll': sgAllWords.join(','),
        'sgDupes': sgAllWords.where(sgIsDupe).join(','),
        'lastChat': chat.isEmpty ? '' : '${chat.last.name}|${chat.last.text}',
        'allReady': allReady,
        'myReady': me?.ready ?? false,
        'readyCount': readyCount,
        'host': hostId,
        'plist': [
          for (final p in players) {'score': p.score, 'words': p.words.length},
        ],
        'sketchWord': sketchWord,
        'sketchDrawer': sketchDrawer,
        'sketchSolved': sketchSolved,
        'sketchStrokes': sketchStrokes.length,
        'chessMoves': chessMoves.join(','),
        'chessWinner': chessWinner,
        'chessWhite': chessWhite,
        'chessBlack': chessBlack,
        'goMoves': goMoves.join(','),
        'goWinner': goWinner,
        'goBlack': goBlack,
        'goWhite': goWhite,
        'wtMoves': wtMoves.length,
        'wtWinner': wtWinner,
        'wtSeats': wtSeats,
        'wtMyRack': wtMyRack.join(','),
        'wtMyScore': wtMyScore,
        'wtScores': {
          for (var i = 0; i < wtSeats.length; i++) wtSeats[i]: wtScoreOf(i),
        },
        'pids': [for (final p in players) p.id],
        'synced': _syncedFromOthers,
        'stateSent': stateSent,
        'stateReceived': stateReceived,
        'glue': _glueStats(),
        'debugLog': debugLog.join(' | '),
        'hostId': hostId,
      };

  String _lastError = '';

  @override
  void dispose() {
    _ticker?.cancel();
    _eventsSub?.cancel();
    super.dispose();
  }
}
