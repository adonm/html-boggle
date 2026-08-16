/// Capture Chess: full piece movement, win by king capture, pawns
/// auto-queen, no castling. Replicated move log; seats pinned at round
/// start so a late spectator can never steal one.
library;

import '../chess.dart';
import 'game_logic.dart';

class ChessLogic extends GameLogic {
  ChessLogic(super.host);

  @override
  String get wireName => 'chess';

  final List<String> moves = [];
  String winner = '';
  String white = '';
  String black = '';

  @override
  bool get needsTwoPlayers => true;

  @override
  String get startToast => 'Round ${host.round} - white moves first';

  @override
  void populateStart(Map<String, dynamic> msg) {
    moves.clear();
    winner = '';
    final seats = host.sortedPlayers;
    white = seats[0].id;
    black = seats.length > 1 ? seats[1].id : '';
    host.deadline = DateTime.now().add(const Duration(hours: 1));
    msg['white'] = white;
    msg['black'] = black;
  }

  @override
  void applyStart(Map<String, dynamic> m) {
    moves.clear();
    winner = '';
    white = (m['white'] as String?) ?? '';
    black = (m['black'] as String?) ?? '';
  }

  bool get whiteTurn => moves.length.isEven;
  String get turnId => whiteTurn ? white : black;
  @override
  bool get isMyTurn => host.meId == turnId;

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
      // The move log is append-only: a freshly elected host may broadcast a
      // stale snapshot; never truncate the local log - keep the longer one.
      final incoming = [for (final v in cm) if (v is String) v];
      if (incoming.length >= moves.length) {
        moves
          ..clear()
          ..addAll(incoming);
      }
    }
    final cw = m['chessWinner'];
    if (cw is String && cw.isNotEmpty && winner.isEmpty) winner = cw;
    final cwt = m['chessWhite'];
    if (cwt is String && cwt.isNotEmpty) white = cwt;
    final cbt = m['chessBlack'];
    if (cbt is String && cbt.isNotEmpty) black = cbt;
  }

  @override
  Map<String, dynamic> debugJson() => {
        'chessMoves': moves.join(','),
        'chessWinner': winner,
        'chessWhite': white,
        'chessBlack': black,
      };

  @override
  void reset() {
    moves.clear();
    winner = '';
    white = '';
    black = '';
  }

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
      winner = 'white';
      host.addScore(white, 1);
      host.endRound();
      host.showToast('White captures the king - white wins!');
      return;
    }
    if (before.contains('K') && !after.contains('K')) {
      winner = 'black';
      host.addScore(black, 1);
      host.endRound();
      host.showToast('Black captures the king - black wins!');
    }
  }
}
