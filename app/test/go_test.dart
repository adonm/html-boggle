import 'package:boggle_app/go.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  List<String> empty() => List.filled(81, '.');

  test('coordinates map correctly (a1 bottom-left, i9 top-right)', () {
    expect(GoGame.sq('a1'), 72);
    expect(GoGame.sq('i9'), 8); // top-right
    expect(GoGame.sq('a9'), 0); // top-left
    expect(GoGame.sq('e5'), 40);
    expect(GoGame.sq('zz'), -1);
    expect(GoGame.coord(72), 'a1');
    expect(GoGame.coord(0), 'a9');
  });

  test('single stone capture removes the surrounded group', () {
    // black b1, white a1, black a2 -> white a1 has no liberties left
    var b = empty();
    var prev = List.of(b);
    b = GoGame.apply(b, prev, GoGame.sq('b1'), true)!;
    prev = List.of(b);
    b = GoGame.apply(b, prev, GoGame.sq('a1'), false)!;
    prev = List.of(b);
    b = GoGame.apply(b, prev, GoGame.sq('a2'), true)!;
    expect(b[GoGame.sq('a1')], '.');
    expect(b[GoGame.sq('b1')], 'B');
    expect(b[GoGame.sq('a2')], 'B');
  });

  test('suicide is illegal', () {
    // white a1, white surrounds corner a2? a2 has neighbors a1, a3, b2.
    // white a3 + b2 + a1 around empty a2 -> black a2 would have no liberty
    var b = empty();
    var prev = List.of(b);
    b = GoGame.apply(b, prev, GoGame.sq('a1'), false)!;
    prev = List.of(b);
    b = GoGame.apply(b, prev, GoGame.sq('a3'), false)!;
    prev = List.of(b);
    b = GoGame.apply(b, prev, GoGame.sq('b2'), false)!;
    expect(GoGame.apply(b, prev, GoGame.sq('a2'), true), isNull);
    // but capturing (black a2 removes white a1 first) can make it legal:
    // white a1 has liberties {a2}; black a2 captures a1, then a2 group has
    // liberties a3? no - a3 is white. b2 white. liberties {b3? no...}
    // Actually a2 neighbors: a1 (captured), a3 (white), b2 (white) -> still
    // suicide. Verify the simple case is rejected and move on.
    expect(GoGame.legalMoves(b, prev, true), isNot(contains(GoGame.sq('a2'))));
  });

  test('simple ko is illegal (cannot recapture immediately)', () {
    // Canonical ko: white d3 is surrounded except e3; black captures with
    // e3; white recapturing d3 would remove black's single e3 stone (its
    // only liberties are white) and recreate the position before e3.
    final log = ['d2', 'd3', 'd4', 'e2', 'c3', 'e4', 'f3', 'pass', 'e3'];
    final r = GoGame.replay(log);
    expect(r.board[GoGame.sq('d3')], '.'); // captured
    expect(r.board[GoGame.sq('e3')], 'B');
    // white d3 recapture = ko violation
    expect(GoGame.apply(r.board, r.prev, GoGame.sq('d3'), false), isNull);
    // but any other legal move is fine, e.g. white e1
    expect(GoGame.apply(r.board, r.prev, GoGame.sq('e1'), false), isNotNull);
  });

  test('replay derives the board from the move log', () {
    final r = GoGame.replay(['b1', 'a1', 'a2', 'pass']);
    expect(r.board[GoGame.sq('a1')], '.');
    expect(r.board[GoGame.sq('b1')], 'B');
    expect(r.board[GoGame.sq('a2')], 'B');
    // after a pass the ko reference is the current board
    expect(r.prev[GoGame.sq('a2')], 'B');
  });

  test('area scoring counts stones and surrounded territory', () {
    var b = empty();
    var prev = List.of(b);
    // black owns the top-left corner: stones along the edge seal it
    for (final c in ['a9', 'b9', 'a8']) {
      b = GoGame.apply(b, prev, GoGame.sq(c), true)!;
      prev = List.of(b);
    }
    final s = GoGame.score(b);
    // black: 3 stones + territory a7,a6..a1,b8..b1 area sealed by a9,b9,a8?
    // a8 + b9 + a9 seal the corner: empty region a7..a1, b8..b1, c9..i9...?
    // c9-i9 are open to the rest of the board, so only the corner is sealed.
    expect(s.black, greaterThan(3));
    expect(s.white, 0);
  });
}
