/// Boggle: 4x4 grid, word paths, host-arbitrated claims with optimistic
/// submissions and retries on non-host clients.
library;

import 'package:flutter/services.dart';

import '../board.dart';
import 'game_logic.dart';

const Duration pendingRetry = Duration(seconds: 5);

class BoggleLogic extends GameLogic {
  BoggleLogic(super.host);

  @override
  String get wireName => 'boggle';

  List<String> board = const [];
  final List<int> path = [];
  String? pendingWord;
  DateTime? pendingSentAt;

  String get currentWord => path.map((i) => board[i]).join();

  /// Placeholder board before the first round (the served board always
  /// arrives with the start/state messages).
  void seedPlaceholder() {
    board = generateBoard(host.rng);
    host.finder.board = board;
  }

  @override
  void populateStart(Map<String, dynamic> msg) {
    path.clear();
    pendingWord = null;
    board = generateBoard(host.rng);
    host.finder.board = board;
    msg['board'] = board.join(',');
  }

  @override
  void applyStart(Map<String, dynamic> m) {
    path.clear();
    pendingWord = null;
    _adoptBoard(m);
  }

  @override
  void onMessage(String type, Map<String, dynamic> m, String from) {
    switch (type) {
      case 'claim':
        _onClaim(m, from);
      case 'award':
        _onAward(m, from);
      case 'reject':
        _onReject(m, from);
    }
  }

  @override
  void onTick() {
    if (host.phase != Phase.play) return;
    if (pendingWord != null &&
        !host.isHost &&
        (pendingSentAt == null ||
            DateTime.now().difference(pendingSentAt!) >= pendingRetry)) {
      pendingSentAt = DateTime.now();
      _sendClaim(pendingWord!);
    }
  }

  @override
  Map<String, dynamic> stateJson() => {'board': board.join(',')};

  @override
  void adoptState(Map<String, dynamic> m) {
    if (host.phase == Phase.play) _adoptBoard(m);
  }

  @override
  Map<String, dynamic> debugJson() => {'board': board.join(','), 'cur': currentWord};

  @override
  void reset() {
    path.clear();
    pendingWord = null;
    board = const [];
  }

  // ------------------------------------------------------------- tile input

  void tapTile(int idx) {
    if (host.phase != Phase.play) return;
    if (path.isNotEmpty && path.last == idx) {
      path.removeLast();
      host.notifyListeners();
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
    host.notifyListeners();
  }

  void popTile() {
    if (path.isNotEmpty) {
      path.removeLast();
      host.notifyListeners();
    }
  }

  void clearPath() {
    if (path.isNotEmpty) {
      path.clear();
      host.notifyListeners();
    }
  }

  void submitWord() {
    if (host.phase != Phase.play || path.isEmpty) return;
    final word = currentWord;
    final me = host.players.where((p) => p.id == host.meId).firstOrNull;
    path.clear();
    if (me == null) return;
    if (word.length < 3) {
      host.pulseWordAttempt();
      host.showToast('Words need at least 3 letters');
      host.notifyListeners();
      return;
    }
    if (me.words.contains(word)) {
      host.pulseWordAttempt();
      host.showToast('You already found "$word"');
      host.notifyListeners();
      return;
    }
    if (host.players.any((p) => p.id != host.meId && p.words.contains(word))) {
      host.pulseWordAttempt();
      host.showToast('"$word" is already taken');
      host.notifyListeners();
      return;
    }
    if (!host.finder.hasWord(word)) {
      host.pulseWordAttempt();
      host.showToast('"$word" is not in the dictionary');
      host.notifyListeners();
      return;
    }
    if (!host.finder.forms(word)) {
      host.pulseWordAttempt();
      host.showToast('"$word" is not on the board');
      host.notifyListeners();
      return;
    }
    if (host.isHost) {
      me.words.add(word);
      me.score += scoreForLen(word.length);
      _sendAward(word, host.meId);
      host.pulseAward();
      host.showToast('+${scoreForLen(word.length)} for "$word"!');
    } else {
      // optimistic: host arbitrates; retried until acknowledged
      me.words.add(word);
      me.score += scoreForLen(word.length);
      pendingWord = word;
      pendingSentAt = DateTime.now();
      _sendClaim(word);
      HapticFeedback.selectionClick();
      host.showToast('Submitted "$word"');
    }
    host.notifyListeners();
  }

  /// Test/debug hook: submit a word as if tapped out and confirmed.
  void debugSubmit(String word) {
    if (host.phase != Phase.play) return;
    final p = host.finder.findPath(word.toLowerCase());
    if (p == null) return;
    path
      ..clear()
      ..addAll(p);
    submitWord();
  }

  // ---------------------------------------------------------------- claims

  void _sendClaim(String word) => host.send({
        't': 'claim',
        'node': host.meId,
        'word': word,
        'name': host.myName,
      });

  void _sendAward(String word, String node) => host.send({
        't': 'award',
        'node': node,
        'word': word,
        'points': scoreForLen(word.length),
      });

  void _sendReject(String word, String node, String reason) =>
      host.send({'t': 'reject', 'node': node, 'word': word, 'reason': reason});

  void _onClaim(Map<String, dynamic> m, String from) {
    if (!host.isHost) return;
    final word = ((m['word'] as String?) ?? '').toLowerCase();
    final p = host.players.where((p) => p.id == from).firstOrNull;
    if (p == null || host.phase != Phase.play) return;
    if (word.length < 3 || word.length > 16) {
      _sendReject(word, from, 'invalid');
      return;
    }
    if (p.words.contains(word)) {
      _sendAward(word, from); // idempotent re-ack: the award was lost
      return;
    }
    if (host.players.any((q) => q.id != from && q.words.contains(word))) {
      _sendReject(word, from, 'taken');
      return;
    }
    if (!host.finder.hasWord(word) || !host.finder.forms(word)) {
      _sendReject(word, from, 'invalid');
      return;
    }
    p.words.add(word);
    p.score += scoreForLen(word.length);
    _sendAward(word, from);
    host.showToast('${p.name.isEmpty ? 'Someone' : p.name} found "$word"');
  }

  void _onAward(Map<String, dynamic> m, String from) {
    final word = ((m['word'] as String?) ?? '').toLowerCase();
    final p = host.players.where((p) => p.id == from).firstOrNull;
    if (p == null || host.phase != Phase.play) return;
    if (p.words.contains(word)) {
      if (p.isMe && pendingWord == word) pendingWord = null;
      return;
    }
    p.words.add(word);
    p.score += scoreForLen(word.length);
    if (p.isMe && pendingWord == word) pendingWord = null;
    host.pulseAward();
    if (!p.isMe) {
      host.showToast(
          '${p.name.isEmpty ? 'Someone' : p.name}: "$word" +${scoreForLen(word.length)}');
    }
  }

  void _onReject(Map<String, dynamic> m, String from) {
    if (from != host.meId) return;
    final word = ((m['word'] as String?) ?? '').toLowerCase();
    if (pendingWord == word) pendingWord = null;
    host.players
        .where((p) => p.id == host.meId)
        .firstOrNull
        ?.words
        .remove(word);
    host.showToast('"$word" rejected: ${m['reason'] ?? 'no'}');
  }

  // ------------------------------------------------------------------ board

  /// Adopt the board served by the round starter (start/state messages).
  /// Falls back to the deterministic derivation if the message has none.
  void _adoptBoard(Map<String, dynamic> m) {
    final b = m['board'];
    if (b is String) {
      final tiles = b.split(',');
      if (tiles.length == 16 && tiles.every((t) => t.isNotEmpty)) {
        board = tiles;
        host.finder.board = board;
        return;
      }
    }
    board = deriveBoard(host.room, host.round);
    host.finder.board = board;
  }
}
