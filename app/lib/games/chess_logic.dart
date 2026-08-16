/// Capture Chess: full piece movement, win by king capture, pawns
/// auto-queen, no castling. Replicated move log; seats pinned at round
/// start so a late spectator can never steal one.
library;

import '../chess.dart';
import 'game_logic.dart';
import 'turn_game.dart';

class ChessLogic extends TurnGameLogic<String> {
  ChessLogic(super.host);

  @override
  String get wireName => 'chess';

  @override
  String get startToast => 'Round ${host.round} - white moves first';

  /// White = seats[0], black = seats[1].
  String get white => seats.isEmpty ? '' : seats[0];
  String get black => seats.length < 2 ? '' : seats[1];
  bool get whiteTurn => moves.length.isEven;
  @override
  String get turnId => whiteTurn ? white : black;

  @override
  void populateStart(Map<String, dynamic> msg) {
    moves.clear();
    winner = '';
    pinSeats(2);
    msg['white'] = white;
    msg['black'] = black;
  }

  @override
  void applyStart(Map<String, dynamic> m) {
    moves.clear();
    winner = '';
    seats = [
      (m['white'] as String?) ?? '',
      (m['black'] as String?) ?? '',
    ]..removeWhere((s) => s.isEmpty);
  }

  @override
  void onMessage(String type, Map<String, dynamic> m, String from) {
    if (type != 'chessMove') return;
    if (host.phase != Phase.play) return;
    _applyMove(m, from);
  }

  @override
  Map<String, dynamic> stateJson() => {
        'chessMoves': moves,
        'chessWinner': winner,
        'chessWhite': white,
        'chessBlack': black,
      };

  @override
  void adoptState(Map<String, dynamic> m) {
    final cm = m['chessMoves'];
    if (cm is List) {
      adoptLonger([for (final v in cm) if (v is String) v]);
    }
    adoptWinner(m['chessWinner']);
    final w = adoptNonEmpty(white, m['chessWhite']);
    final b = adoptNonEmpty(black, m['chessBlack']);
    if (w != white || b != black) seats = [w, b];
  }

  @override
  Map<String, dynamic> debugJson() => {
        'chessMoves': moves.join(','),
        'chessWinner': winner,
        'chessWhite': white,
        'chessBlack': black,
      };

  // ------------------------------------------------------------------ moves

  /// Current player: attempt a move from-to ("e2", "e4").
  bool tryMove(String from, String to) {
    if (host.phase != Phase.play || winner.isNotEmpty) return false;
    if (host.meId != turnId) return false;
    final f = ChessBoard.sq(from);
    final t = ChessBoard.sq(to);
    if (f < 0 || t < 0 || f == t) return false;
    final b = ChessBoard.fromMoves(moves);
    if (!ChessBoard.targets(b, f).contains(t)) return false;
    moves.add('${from}${to}');
    host.send({'t': 'chessMove', 'node': host.meId, 'from': from, 'to': to});
    _checkEnd(b);
    host.notifyListeners();
    return true;
  }

  void _applyMove(Map<String, dynamic> m, String from) {
    if (winner.isNotEmpty || from != turnId) return;
    final f = ChessBoard.sq((m['from'] as String?) ?? '');
    final t = ChessBoard.sq((m['to'] as String?) ?? '');
    if (f < 0 || t < 0 || f == t) return;
    final b = ChessBoard.fromMoves(moves);
    if (!ChessBoard.targets(b, f).contains(t)) return;
    moves.add('${m['from']}${m['to']}');
    _checkEnd(b);
    host.notifyListeners();
  }

  void _checkEnd(List<String> before) {
    // A capture is simply the king disappearing from the board.
    final after = ChessBoard.fromMoves(moves);
    if (before.contains('k') && !after.contains('k')) {
      finish('white', winnerId: white);
      host.showToast('White captures the king - white wins!');
      return;
    }
    if (before.contains('K') && !after.contains('K')) {
      finish('black', winnerId: black);
      host.showToast('Black captures the king - black wins!');
    }
  }
}
