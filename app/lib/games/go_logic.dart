/// Go (9x9): stones, captures, suicide ban, simple ko, area scoring.
/// Replicated move log; two consecutive passes end the game.
library;

import '../go.dart';
import 'game_logic.dart';
import 'turn_game.dart';

class GoLogic extends TurnGameLogic<String> {
  GoLogic(super.host);

  @override
  String get wireName => 'go';

  @override
  String get startToast => 'Round ${host.round} - black moves first';

  /// Black = seats[0] (moves first), white = seats[1].
  String get black => seats.isEmpty ? '' : seats[0];
  String get white => seats.length < 2 ? '' : seats[1];
  bool get blackTurn => moves.length.isEven;
  @override
  String get turnId => blackTurn ? black : white;

  @override
  void populateStart(Map<String, dynamic> msg) {
    moves.clear();
    winner = '';
    pinSeats(2);
    // solo practice: one player sits both sides
    if (host.players.length < 2) seats = [host.meId, host.meId];
    msg['black'] = black;
    msg['white'] = white;
  }

  @override
  void applyStart(Map<String, dynamic> m) {
    moves.clear();
    winner = '';
    seats = [
      (m['black'] as String?) ?? '',
      (m['white'] as String?) ?? '',
    ]..removeWhere((s) => s.isEmpty);
  }

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
        finish(from == black ? 'white' : 'black',
            winnerId: from == black ? white : black);
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
      adoptLonger([for (final v in gm) if (v is String) v]);
    }
    adoptWinner(m['goWinner']);
    final b = adoptNonEmpty(black, m['goBlack']);
    final w = adoptNonEmpty(white, m['goWhite']);
    if (b != black || w != white) seats = [b, w];
  }

  @override
  Map<String, dynamic> debugJson() => {
        'goMoves': moves.join(','),
        'goWinner': winner,
        'goBlack': black,
        'goWhite': white,
      };

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
    final resignedBlack = host.meId == black;
    finish(resignedBlack ? 'white' : 'black',
        winnerId: resignedBlack ? white : black);
    host.send({'t': 'goResign', 'node': host.meId});
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
      final label = s.black == s.white
          ? 'draw'
          : (s.black > s.white ? 'black' : 'white');
      finish(label,
          winnerId: label == 'black'
              ? black
              : label == 'white'
                  ? white
                  : null);
    }
  }
}
