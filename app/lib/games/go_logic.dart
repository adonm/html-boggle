/// Go (9x9): stones, captures, suicide ban, simple ko, area scoring.
/// Replicated move log; two consecutive passes end the game.
library;

import '../go.dart';
import 'game_logic.dart';

class GoLogic extends GameLogic {
  GoLogic(super.host);

  @override
  String get wireName => 'go';

  final List<String> moves = [];
  String winner = '';
  String black = '';
  String white = '';

  @override
  bool get needsTwoPlayers => true;

  @override
  String get startToast => 'Round ${host.round} - black moves first';

  @override
  void populateStart(Map<String, dynamic> msg) {
    moves.clear();
    winner = '';
    final seats = host.sortedPlayers;
    black = seats[0].id;
    white = seats.length > 1 ? seats[1].id : '';
    host.deadline = DateTime.now().add(const Duration(hours: 1));
    msg['black'] = black;
    msg['white'] = white;
  }

  @override
  void applyStart(Map<String, dynamic> m) {
    moves.clear();
    winner = '';
    black = (m['black'] as String?) ?? '';
    white = (m['white'] as String?) ?? '';
  }

  bool get blackTurn => moves.length.isEven; // black moves first
  String get turnId => blackTurn ? black : white;
  @override
  bool get isMyTurn => host.meId == turnId;

  @override
  void onMessage(String type, Map<String, dynamic> m, String from) {
    switch (type) {
      case 'goMove':
        if (host.phase != Phase.play) return;
        _applyMove(m, from);
      case 'goPass':
        if (host.phase != Phase.play) return;
        _applyPass(from);
      case 'goResign':
        if (host.phase != Phase.play) return;
        if (from != black && from != white) return;
        winner = from == black ? 'white' : 'black';
        _end();
    }
  }

  @override
  Map<String, dynamic> stateJson() => {
        'goMoves': moves,
        'goWinner': winner,
        'goBlack': black,
        'goWhite': white,
      };

  @override
  void adoptState(Map<String, dynamic> m) {
    final gm = m['goMoves'];
    if (gm is List) {
      final incoming = [for (final v in gm) if (v is String) v];
      if (incoming.length >= moves.length) {
        moves
          ..clear()
          ..addAll(incoming);
      }
    }
    final gw = m['goWinner'];
    if (gw is String && gw.isNotEmpty && winner.isEmpty) winner = gw;
    final gb = m['goBlack'];
    if (gb is String && gb.isNotEmpty) black = gb;
    final gwt = m['goWhite'];
    if (gwt is String && gwt.isNotEmpty) white = gwt;
  }

  @override
  Map<String, dynamic> debugJson() => {
        'goMoves': moves.join(','),
        'goWinner': winner,
        'goBlack': black,
        'goWhite': white,
      };

  @override
  void reset() {
    moves.clear();
    winner = '';
    black = '';
    white = '';
  }

  // ------------------------------------------------------------------ moves

  /// Current player: place a stone at a coordinate ("b3").
  bool tryMove(String coord) {
    if (host.phase != Phase.play) return false;
    if (winner.isNotEmpty || host.meId != turnId) return false;
    final r = GoGame.replay(moves);
    final idx = GoGame.sq(coord);
    if (GoGame.apply(r.board, r.prev, idx, blackTurn) == null) {
      host.showToast('illegal move');
      return false;
    }
    moves.add(coord);
    host.send({'t': 'goMove', 'node': host.meId, 'coord': coord});
    host.notifyListeners();
    return true;
  }

  void passTurn() {
    if (host.phase != Phase.play) return;
    if (winner.isNotEmpty || host.meId != turnId) return;
    moves.add('pass');
    host.send({'t': 'goPass', 'node': host.meId});
    _checkEnd();
    host.notifyListeners();
  }

  void resign() {
    if (host.phase != Phase.play) return;
    if (host.meId != black && host.meId != white) return;
    winner = host.meId == black ? 'white' : 'black';
    host.send({'t': 'goResign', 'node': host.meId});
    _end();
    host.notifyListeners();
  }

  void _applyMove(Map<String, dynamic> m, String from) {
    if (winner.isNotEmpty || from != turnId) return;
    final r = GoGame.replay(moves);
    final idx = GoGame.sq((m['coord'] as String?) ?? '');
    if (GoGame.apply(r.board, r.prev, idx, blackTurn) == null) return;
    moves.add((m['coord'] as String?) ?? '');
    host.notifyListeners();
  }

  void _applyPass(String from) {
    if (winner.isNotEmpty || from != turnId) return;
    moves.add('pass');
    _checkEnd();
    host.notifyListeners();
  }

  /// Two consecutive passes end the game; area scoring decides.
  void _checkEnd() {
    if (winner.isNotEmpty || moves.length < 2) return;
    if (moves[moves.length - 1] == 'pass' &&
        moves[moves.length - 2] == 'pass') {
      final r = GoGame.replay(moves);
      final s = GoGame.score(r.board);
      winner = s.black == s.white
          ? 'draw'
          : (s.black > s.white ? 'black' : 'white');
      _end();
    }
  }

  void _end() {
    final winnerId = switch (winner) {
      'black' => black,
      'white' => white,
      _ => '',
    };
    host.addScore(winnerId, 1);
    host.endRound();
    host.showToast('Game over!');
  }
}
