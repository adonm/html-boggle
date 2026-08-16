import 'dart:math';

import 'package:boggle_app/board.dart';
import 'package:boggle_app/games/game_logic.dart';
import 'package:boggle_app/games/turn_game.dart';
import 'package:flutter_test/flutter_test.dart';

/// Minimal fake host for testing game logics in isolation.
class FakeHost implements GameHost {
  final List<Map<String, dynamic>> sent = [];
  final List<String> toasts = [];
  final List<({String id, int points})> scores = [];
  DateTime? deadlineAt;
  int endedRounds = 0;
  int awardPulses = 0;
  int wordAttemptPulses = 0;

  @override
  String get meId => 'me';
  @override
  String get myName => 'me';
  @override
  Phase get phase => Phase.play;
  @override
  List<Player> get players =>
      [Player('a', 'A'), Player('me', 'Me'), Player('b', 'B')];
  @override
  List<Player> get sortedPlayers =>
      [...players]..sort((a, b) => a.id.compareTo(b.id));
  @override
  bool get isHost => true;
  @override
  Random get rng => Random(7);
  @override
  WordFinder get finder => WordFinder(const []);
  @override
  String get room => 'test';
  @override
  int get round => 1;
  @override
  DateTime? get deadline => deadlineAt;
  @override
  set deadline(DateTime? value) => deadlineAt = value;
  @override
  void send(Map<String, dynamic> m) => sent.add(m);
  @override
  void showToast(String msg) => toasts.add(msg);
  @override
  void pulseWordAttempt() => wordAttemptPulses++;
  @override
  void pulseAward() => awardPulses++;
  @override
  void addScore(String playerId, int points) =>
      scores.add((id: playerId, points: points));
  @override
  void endRound() => endedRounds++;
  @override
  void notifyListeners() {}
}

/// Tiny replicated-log game: two seats take turns appending a tag.
class TagGame extends TurnGameLogic<String> {
  TagGame(super.host);

  @override
  String get wireName => 'tag';
  @override
  String get turnId =>
      seats.length < 2 ? '' : seats[moves.length % seats.length];
  @override
  void populateStart(Map<String, dynamic> msg) {
    moves.clear();
    winner = '';
    pinSeats(2);
  }
  @override
  void applyStart(Map<String, dynamic> m) {}
  @override
  void onMessage(String type, Map<String, dynamic> m, String from) {}
  @override
  Map<String, dynamic> stateJson() => {'tagMoves': moves, 'tagWinner': winner};
  @override
  Map<String, dynamic> debugJson() => const {};
}

void main() {
  test('adoptNonEmpty and adoptStickyBool keep local state on stale data', () {
    expect(adoptNonEmpty('keep', null), 'keep');
    expect(adoptNonEmpty('keep', ''), 'keep');
    expect(adoptNonEmpty('keep', 'new'), 'new');
    expect(adoptStickyBool(false, null), false);
    expect(adoptStickyBool(false, true), true);
    expect(adoptStickyBool(true, false), true); // never regresses
  });

  test('pinSeats picks the two smallest ids and sets a long deadline', () {
    final host = FakeHost();
    final g = TagGame(host);
    g.populateStart({});
    expect(g.seats, ['a', 'b']); // 'me' > 'b' alphabetically
    expect(host.deadlineAt!.difference(DateTime.now()).inMinutes > 55, true);
  });

  test('turn rotates with the log and isMyTurn follows it', () {
    final host = FakeHost();
    final g = TagGame(host);
    g.populateStart({});
    // seats are 'a' and 'b'; the fake host plays as 'me' (spectator)
    expect(g.isMyTurn, false);
    g.moves.add('x');
    g.moves.add('y');
    expect(g.turnId, 'a');
    // a two-seat game with our own id as a seat
    final g2 = TagGame(FakeHost())..seats = ['me', 'b'];
    expect(g2.isMyTurn, true); // first turn is ours
    g2.moves.add('x');
    expect(g2.isMyTurn, false);
    g2.moves.add('y');
    expect(g2.isMyTurn, true);
  });

  test('adoptLonger never truncates the local log', () {
    final g = TagGame(FakeHost());
    g.moves.addAll(['a', 'b', 'c']);
    g.adoptLonger(['a']); // stale snapshot
    expect(g.moves, ['a', 'b', 'c']);
    g.adoptLonger(['a', 'b', 'c', 'd']); // ahead
    expect(g.moves, ['a', 'b', 'c', 'd']);
  });

  test('winner adoption is sticky', () {
    final g = TagGame(FakeHost());
    g.adoptWinner('x');
    g.adoptWinner('');
    g.adoptWinner('y');
    expect(g.winner, 'x');
  });

  test('finish ends the round and scores exactly once for the winner', () {
    final host = FakeHost();
    final g = TagGame(host);
    g.finish('me', winnerId: 'me');
    expect(g.winner, 'me');
    expect(host.endedRounds, 1);
    expect(host.scores, [(id: 'me', points: 1)]);
    expect(host.toasts, ['Game over!']);
    // draws score nobody
    final h2 = FakeHost();
    TagGame(h2).finish('draw', winnerId: null);
    expect(h2.scores, isEmpty);
  });

  test('reset clears the log, winner, and seats', () {
    final g = TagGame(FakeHost());
    g.populateStart({});
    g.moves.add('x');
    g.finish('a', winnerId: 'a');
    g.reset();
    expect(g.moves, isEmpty);
    expect(g.winner, '');
    expect(g.seats, isEmpty);
  });
}
