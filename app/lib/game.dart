/// The room shell: presence, chat, ready-up flow, deterministic host,
/// state snapshots, and the gossip message protocol. Game rules live in
/// `games/*_logic.dart` behind the [GameLogic] interface; the shell only
/// routes messages, replicates state, and keeps the phase machine.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'board.dart';
import 'games/boggle_logic.dart';
import 'games/chess_logic.dart';
import 'games/game_logic.dart';
import 'games/go_logic.dart';
import 'games/scatter_logic.dart';
import 'games/sketch_logic.dart';
import 'games/wt_logic.dart';
import 'net.dart';

export 'games/game_logic.dart' show GameMode, GameModeInfo, Phase, Player;

@JS('window.localStorage')
external JSObject get _storage;

@JS('window')
external JSObject get _window;

const int roundMs = 180000;

const Duration helloInterval = Duration(seconds: 5);
const Duration stateInterval = Duration(seconds: 10);
const Duration playerTimeout = Duration(seconds: 45);
const Duration leaderTimeout = Duration(seconds: 25);
const Duration wantStateInterval = Duration(seconds: 2);

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

/// The room shell + host for the active game logic.
class Game extends ChangeNotifier implements GameHost {
  final NetBridge net = NetBridge.instance;
  final Random _rng = Random();

  WordFinder finder = WordFinder(const []);

  Phase phase = Phase.lobby;
  final List<Player> players = [];
  String meId = '';
  String myName = '';
  String room = '';
  DateTime? deadline;
  int round = 0;
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

  String get hostId => players.isEmpty
      ? ''
      : players.map((p) => p.id).reduce((a, b) => a.compareTo(b) < 0 ? a : b);
  bool get isHost => meId.isNotEmpty && meId == hostId;
  Player? get me => players.where((p) => p.id == meId).firstOrNull;
  int get totalScore => players.fold(0, (a, p) => a + p.score);
  bool get allReady => players.isNotEmpty && players.every((p) => p.ready);
  int get readyCount => players.where((p) => p.ready).length;

  /// Canonical player order (by node id) - identical on every client, used
  /// for role assignment (seats, drawer rotation).
  List<Player> get sortedPlayers =>
      [...players]..sort((a, b) => a.id.compareTo(b.id));

  String _lastHostId = '';
  bool _syncedFromOthers = false; // adopted state/hello from another player
  DateTime? lastWantStateAt;
  int stateSent = 0;
  int stateReceived = 0;
  final List<String> debugLog = [];

  void _log(String what) {
    debugLog.add('${DateTime.now().millisecondsSinceEpoch % 100000} $what');
    if (debugLog.length > 40) debugLog.removeAt(0);
  }

  // ----------------------------------------------------------- game logic

  GameMode mode = GameMode.boggle;
  late GameLogic _logic = createLogic(GameMode.boggle, this);

  GameLogic get logic => _logic;
  BoggleLogic? get boggle => _logic is BoggleLogic ? _logic as BoggleLogic : null;
  ScatterLogic? get scatter => _logic is ScatterLogic ? _logic as ScatterLogic : null;
  SketchLogic? get sketch => _logic is SketchLogic ? _logic as SketchLogic : null;
  ChessLogic? get chess => _logic is ChessLogic ? _logic as ChessLogic : null;
  GoLogic? get go => _logic is GoLogic ? _logic as GoLogic : null;
  WtLogic? get wt => _logic is WtLogic ? _logic as WtLogic : null;

  void _ensureLogic() {
    if (_logic.wireName != mode.wireName) {
      _logic = createLogic(mode, this);
    }
  }

  void setMode(GameMode m) {
    if (m == mode) return;
    if (phase == Phase.lobby || phase == Phase.room || phase == Phase.results) {
      mode = m;
      _ensureLogic();
      notifyListeners();
    }
  }

  // ------------------------------------------------------------ GameHost

  @override
  Random get rng => _rng;

  @override
  void pulseWordAttempt() {
    wordAttempts++;
    HapticFeedback.selectionClick();
    notifyListeners();
  }

  @override
  void pulseAward() {
    awardPulse++;
    HapticFeedback.mediumImpact();
  }

  @override
  void addScore(String playerId, int points) {
    final p = players.where((p) => p.id == playerId).firstOrNull;
    if (p != null) p.score += points;
  }

  @override
  void endRound() {
    deadline = DateTime.now().subtract(const Duration(seconds: 1));
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
    // Placeholder board before the first round (the served board always
    // arrives with the start/state messages).
    _ensureLogic();
    boggle?.seedPlaceholder();
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
      ..._logic.stateJson(),
      'players': players.map((p) => p.toJson()).toList(),
    });
  }

  void startRound() {
    if ((phase != Phase.room && phase != Phase.results) || !allReady) return;
    // Whoever starts the round serves authoritative state from here on.
    _syncedFromOthers = true;
    _ensureLogic();
    if (_logic.needsTwoPlayers && players.length < 2) {
      showToast('${mode.title} needs 2 players (others can spectate)');
      return;
    }
    deadline = DateTime.now().add(const Duration(milliseconds: roundMs));
    round++;
    final msg = {
      't': 'start',
      'node': meId,
      'deadline': deadline!.millisecondsSinceEpoch,
      'round': round,
      'mode': mode.wireName,
    };
    _logic.populateStart(msg);
    send(msg);
    _applyStart();
    notifyListeners();
  }

  void _applyStart() {
    for (final p in players) {
      p.words.clear();
      p.ready = false;
    }
    roundEpoch++;
    phase = Phase.play;
    showToast(_logic.startToast);
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
        _ensureLogic();
        _logic.applyStart(m);
        _applyStart();
      case 'chat':
        final text = ((m['text'] as String?) ?? '').trim();
        if (text.isEmpty || node == meId) return;
        chat.add(ChatMessage(
          name: (m['name'] as String?) ?? '',
          text: text,
          fromMe: false,
        ));
        _trimChat();
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
      default:
        // everything else belongs to the active game
        if (t != null && node.isNotEmpty) {
          _logic.onMessage(t, m, node);
        }
    }
  }

  void _applyState(Map<String, dynamic> m) {
    _syncedFromOthers = true;
    stateReceived++;
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
    // Phase-monotonic adoption: a stale snapshot must never regress the
    // players list, phase, or deadline.
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
    _ensureLogic();
    _logic.adoptState(m);
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
      _logic.onTick();
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

  /// Test/debug helper: end the current round immediately.
  void debugEndRound() {
    if (phase == Phase.play) {
      deadline = DateTime.now().subtract(const Duration(seconds: 1));
    }
  }

  /// Test/debug helper: force the room's game mode.
  void debugSetMode(String wireName) {
    mode = modeFromWire(wireName);
    _ensureLogic();
    notifyListeners();
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
    _logic = createLogic(mode, this);
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
        'toast': toast,
        'error': _lastError,
        'mode': mode.name,
        'lastChat': chat.isEmpty ? '' : '${chat.last.name}|${chat.last.text}',
        'allReady': allReady,
        'myReady': me?.ready ?? false,
        'readyCount': readyCount,
        'host': hostId,
        'plist': [
          for (final p in players) {'score': p.score, 'words': p.words.length},
        ],
        'pids': [for (final p in players) p.id],
        'synced': _syncedFromOthers,
        'stateSent': stateSent,
        'stateReceived': stateReceived,
        'glue': _glueStats(),
        'debugLog': debugLog.join(' | '),
        'hostId': hostId,
        ..._logic.debugJson(),
      };

  String _lastError = '';

  @override
  void dispose() {
    _ticker?.cancel();
    _eventsSub?.cancel();
    super.dispose();
  }
}
