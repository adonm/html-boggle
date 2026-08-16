import 'dart:math';

import 'package:boggle_app/board.dart';
import 'package:boggle_app/chess.dart';
import 'package:boggle_app/games/chess_logic.dart';
import 'package:boggle_app/games/game_logic.dart';
import 'package:flutter_test/flutter_test.dart';

/// Solo fake host: the only player sits both chess seats.
class SoloHost implements GameHost {
  final List<String> toasts = [];
  final List<({String id, int points})> scores = [];
  int endedRounds = 0;

  @override
  String get meId => 'me';
  @override
  String get myName => 'me';
  @override
  Phase get phase => Phase.play;
  @override
  List<Player> get players => [Player('me', 'Me')];
  @override
  List<Player> get sortedPlayers => players;
  @override
  bool get isHost => true;
  @override
  Random get rng => Random(1);
  @override
  WordFinder get finder => WordFinder(const []);
  @override
  String get room => 'test';
  @override
  int get round => 1;
  @override
  DateTime? get deadline => null;
  @override
  set deadline(DateTime? value) {}
  @override
  void send(Map<String, dynamic> m) {}
  @override
  void sfx(String name) {}
  @override
  void showToast(String msg) => toasts.add(msg);
  @override
  void pulseWordAttempt() {}
  @override
  void pulseAward() {}
  @override
  void addScore(String playerId, int points) =>
      scores.add((id: playerId, points: points));
  @override
  void endRound() => endedRounds++;
  @override
  void notifyListeners() {}
}

SoloHost hostOf(ChessLogic g) => g.host as SoloHost;

ChessLogic started({String rules = 'standard'}) {
  final h = SoloHost();
  final g = ChessLogic(h);
  g.populateStart({});
  g.setRules(rules);
  return g;
}

void main() {
  test('standard rules: scholar\'s mate checkmates with the engine', () {
    final g = started();
    for (final mv in ['e2e4', 'e7e5', 'f1c4', 'b8c6', 'd1h5', 'g8f6']) {
      expect(g.tryMove(mv.substring(0, 2), mv.substring(2, 4)), true, reason: mv);
    }
    expect(g.tryMove('h5', 'f7'), true);
    expect(g.winner, 'white'); // white delivered mate
    expect(hostOf(g).endedRounds, 1);
    expect(hostOf(g).scores, [(id: 'me', points: 1)]);
  });

  test('standard rules: illegal moves are rejected', () {
    final g = started();
    expect(g.tryMove('e2', 'e5'), false); // pawn 3 squares
    expect(g.tryMove('a1', 'a2'), false); // rook through own pawn
    expect(g.tryMove('e1', 'g1'), false); // castling before clearing
    expect(g.moves, isEmpty);
    // black can't move first
    expect(g.tryMove('e7', 'e5'), false);
  });

  test('standard rules: castling and en passant are legal', () {
    final g = started();
    for (final mv in [
      'e2e4', 'e7e5', 'g1f3', 'b8c6', 'f1c4', 'f8c5', // develop
    ]) {
      expect(g.tryMove(mv.substring(0, 2), mv.substring(2, 4)), true, reason: mv);
    }
    expect(g.tryMove('e1', 'g1'), true); // white castles kingside
    expect(g.tryMove('d7', 'd5'), true);
    expect(g.tryMove('e4', 'd5'), true); // en passant capture
    expect(g.moves.last, 'e4d5');
  });

  test('standard rules: promotion chooses the piece', () {
    final g = started();
    for (final mv in [
      'a2a4', 'b7b5', 'a4b5', 'a7a6', 'b5a6', 'c8b7', 'a6b7', 'b8c6',
    ]) {
      expect(g.tryMove(mv.substring(0, 2), mv.substring(2, 4)), true, reason: mv);
    }
    // pawn b7 -> b8 needs a promotion piece
    expect(g.promotionFor('b7', 'b8'), 'q');
    expect(g.tryMove('b7', 'b8'), false); // without promo: rejected
    expect(g.tryMove('b7', 'b8', promo: 'q'), true);
    expect(g.moves.last, 'b7b8q');
    expect(g.displayBoard[ChessBoard.sq('b8')], 'Q');
  });

  test('capture rules: king capture wins (fool\'s mate)', () {
    final g = started(rules: 'capture');
    for (final mv in ['f2f3', 'e7e5', 'g2g4', 'd8h4', 'a2a3']) {
      expect(g.tryMove(mv.substring(0, 2), mv.substring(2, 4)), true, reason: mv);
    }
    expect(g.tryMove('h4', 'e1'), true);
    expect(g.winner, 'black');
    expect(hostOf(g).scores, [(id: 'me', points: 1)]);
  });

  test('capture rules: moving into check is allowed (no engine gate)', () {
    final g = started(rules: 'capture');
    // white opens the e-file with the black queen able to reach e1 later
    expect(g.tryMove('e2', 'e3'), true);
    expect(g.tryMove('d7', 'd5'), true);
    expect(g.tryMove('e1', 'e2'), true); // king walks forward into danger
  });

  test('rules and seats survive state adoption without regression', () {
    final g = started();
    g.adoptState({
      'chessMoves': ['e2e4'],
      'chessWhite': 'me',
      'chessBlack': 'me',
      'chessWinner': '',
      'chessRules': 'capture',
    });
    expect(g.rules, 'capture');
    expect(g.moves, ['e2e4']);
    // stale snapshot with a shorter log and empty rules must not regress
    g.adoptState({'chessMoves': <String>[], 'chessRules': '', 'chessWinner': 'white'});
    expect(g.moves, ['e2e4']);
    expect(g.rules, 'capture');
    expect(g.winner, 'white'); // local winner was empty, so it adopts
  });
}
