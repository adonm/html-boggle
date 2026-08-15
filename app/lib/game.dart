/// The game: state machine, deterministic host, word arbitration and the
/// gossip message protocol (identical to the previous raylib implementation,
/// so any client version interoperates).
library;

import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'board.dart';
import 'net.dart';

enum Phase { lobby, joining, room, play, results }

class Player {
  Player(this.id, this.name);

  final String id;
  String name;
  int score = 0;
  final Set<String> words = {};
  DateTime lastSeen = DateTime.now();
  bool isMe = false;

  Map<String, dynamic> toJson() => {
        'node': id,
        'name': name,
        'score': score,
        'words': words.toList(),
      };
}

const int roundMs = 180000;
const Duration helloInterval = Duration(seconds: 5);
const Duration stateInterval = Duration(seconds: 10);
const Duration playerTimeout = Duration(seconds: 45);
const Duration pendingRetry = Duration(seconds: 5);

const List<String> randomNames = [
  'Quilt', 'Dicey', 'Zinger', 'Puzzle', 'Bingo', 'Lexi', 'Tango', 'Jumble',
  'Clever', 'Snappy', 'Witty', 'Mango', 'Doodle', 'Fable', 'Pixel', 'Gizmo',
  'Turbo', 'Sunny', 'Rascal', 'Comet', 'Whiz', 'Nimbus', 'Biscuit', 'Echo',
];

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
  Timer? _ticker;
  StreamSubscription? _eventsSub;
  int _seq = 0;

  String get currentWord => path.map((i) => board[i]).join();
  String get hostId => players.isEmpty
      ? ''
      : players.map((p) => p.id).reduce((a, b) => a.compareTo(b) < 0 ? a : b);
  bool get isHost => meId.isNotEmpty && meId == hostId;
  Player? get me => players.where((p) => p.id == meId).firstOrNull;
  int get totalScore => players.fold(0, (a, p) => a + p.score);

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
    board = deriveBoard(rm);
    finder.board = board;
    phase = Phase.joining;
    notifyListeners();
    try {
      final nodeId = await net.join(room: rm, topicHex: topicHex(rm), name: nm);
      meId = nodeId;
      players
        ..clear()
        ..add(Player(meId, nm)..isMe = true);
      pendingWord = null;
      phase = Phase.room;
      lastHello = null;
      lastState = DateTime.now();
      sendHello();
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

  void sendClaim(String word) =>
      send({'t': 'claim', 'node': meId, 'word': word, 'name': myName});

  void sendState() {
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
      'players': players.map((p) => p.toJson()).toList(),
    });
  }

  void startRound() {
    if (phase != Phase.room && phase != Phase.results) return;
    deadline = DateTime.now().add(const Duration(milliseconds: roundMs));
    round++;
    send({
      't': 'start',
      'node': meId,
      'deadline': deadline!.millisecondsSinceEpoch,
      'round': round,
    });
    _applyStart();
    notifyListeners();
  }

  void _applyStart() {
    for (final p in players) {
      p.words.clear();
    }
    path.clear();
    pendingWord = null;
    phase = Phase.play;
    showToast('Round $round - find words!');
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
      showToast('Words need at least 3 letters');
      notifyListeners();
      return;
    }
    if (me.words.contains(word)) {
      showToast('You already found "$word"');
      notifyListeners();
      return;
    }
    if (players.any((p) => p.id != meId && p.words.contains(word))) {
      showToast('"$word" is already taken');
      notifyListeners();
      return;
    }
    if (!finder.hasWord(word)) {
      showToast('"$word" is not in the dictionary');
      notifyListeners();
      return;
    }
    if (!finder.forms(word)) {
      showToast('"$word" is not on the board');
      notifyListeners();
      return;
    }
    if (isHost) {
      me.words.add(word);
      me.score += scoreForLen(word.length);
      sendAward(word, meId);
      showToast('+${scoreForLen(word.length)} for "$word"!');
    } else {
      // optimistic: host arbitrates; retried until acknowledged
      me.words.add(word);
      me.score += scoreForLen(word.length);
      pendingWord = word;
      pendingSentAt = DateTime.now();
      sendClaim(word);
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
          if (isHost) sendState();
        } else {
          if (name.isNotEmpty) p.name = name;
          p.lastSeen = DateTime.now();
        }
      case 'bye':
        _removePlayer(node);
      case 'start':
        final dl = m['deadline'];
        if (dl is num) {
          deadline = DateTime.fromMillisecondsSinceEpoch(dl.toInt());
        }
        final r = m['round'];
        if (r is num) round = r.toInt();
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
        if (!p.isMe) {
          showToast('${p.name.isEmpty ? 'Someone' : p.name}: "$word" +${scoreForLen(word.length)}');
        }
      case 'reject':
        if (node != meId) return;
        final word = ((m['word'] as String?) ?? '').toLowerCase();
        if (pendingWord == word) pendingWord = null;
        me?.words.remove(word);
        showToast('"$word" rejected: ${m['reason'] ?? 'no'}');
      case 'state':
        _applyState(m);
    }
  }

  void _applyState(Map<String, dynamic> m) {
    final list = m['players'];
    if (list is List) {
      players.clear();
      for (final item in list) {
        if (item is! Map) continue;
        final id = item['node'] as String?;
        if (id == null) continue;
        final p = Player(id, (item['name'] as String?) ?? '');
        p.score = (item['score'] as num?)?.toInt() ?? 0;
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
    final ph = m['phase'];
    if (ph == 'play') {
      phase = Phase.play;
      path.clear();
    } else if (ph == 'results') {
      phase = Phase.results;
    } else {
      phase = Phase.room;
    }
    final dl = m['deadline'];
    if (dl is num) deadline = DateTime.fromMillisecondsSinceEpoch(dl.toInt());
    final r = m['round'];
    if (r is num) round = r.toInt();
  }

  // ------------------------------------------------------------------ tick

  void _tick() {
    final now = DateTime.now();
    if (phase == Phase.room || phase == Phase.play || phase == Phase.results) {
      if (lastHello == null || now.difference(lastHello!) >= helloInterval) {
        lastHello = now;
        sendHello();
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
      if (phase == Phase.play && deadline != null && now.isAfter(deadline!)) {
        phase = Phase.results;
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
        'plist': [
          for (final p in players) {'score': p.score, 'words': p.words.length},
        ],
      };

  String _lastError = '';

  @override
  void dispose() {
    _ticker?.cancel();
    _eventsSub?.cancel();
    super.dispose();
  }
}
