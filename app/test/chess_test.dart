import 'package:boggle_app/chess.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('initial setup: 32 pieces in standard places', () {
    final b = ChessBoard.initial();
    var count = 0;
    for (final c in b) {
      if (c != '.') count++;
    }
    expect(count, 32);
    expect(b[0], 'r');
    expect(b[60], 'K');
    expect(b[63], 'R');
    expect(b[8], 'p');
    expect(b[48], 'P');
  });

  test('pawns move one or two, capture diagonally, promote', () {
    var b = ChessBoard.initial();
    expect(ChessBoard.targets(b, ChessBoard.sq('a2')), [
      ChessBoard.sq('a3'),
      ChessBoard.sq('a4'),
    ]);
    b = ChessBoard.apply(b, ChessBoard.sq('a2'), ChessBoard.sq('a4'));
    expect(ChessBoard.targets(b, ChessBoard.sq('a4')), [ChessBoard.sq('a5')]);
    // white pawn captures black pawn after setup moves
    b = ChessBoard.fromMoves(['a2a4', 'b7b5']);
    expect(ChessBoard.targets(b, ChessBoard.sq('a4')),
        contains(ChessBoard.sq('b5')));
    // promotion to queen on the last rank
    var bb = ChessBoard.initial();
    bb[ChessBoard.sq('a7')] = 'P';
    bb[ChessBoard.sq('a8')] = '.';
    bb = ChessBoard.apply(bb, ChessBoard.sq('a7'), ChessBoard.sq('a8'));
    expect(bb[ChessBoard.sq('a8')], 'Q');
    bb = ChessBoard.initial();
    bb[ChessBoard.sq('h2')] = 'p';
    bb[ChessBoard.sq('h1')] = '.';
    bb = ChessBoard.apply(bb, ChessBoard.sq('h2'), ChessBoard.sq('h1'));
    expect(bb[ChessBoard.sq('h1')], 'q');
  });

  test('knights jump over pieces', () {
    final b = ChessBoard.initial();
    expect(ChessBoard.targets(b, ChessBoard.sq('g1')), [
      ChessBoard.sq('f3'),
      ChessBoard.sq('h3'),
    ]);
  });

  test('sliding pieces are blocked by own and enemy pieces', () {
    final b = ChessBoard.fromMoves(['d2d4', 'd7d5', 'c1f4', 'c8f5']);
    // white bishop on f4 sees e5 and g5 (blocked by f5? no - diagonal g5-h6...)
    final targets = ChessBoard.targets(b, ChessBoard.sq('f4'));
    expect(targets, contains(ChessBoard.sq('e5')));
    expect(targets, contains(ChessBoard.sq('g5')));
    expect(targets, contains(ChessBoard.sq('e3')));
    // black queen on d8 has a clear diagonal to d8-h4 after e7 pawn moves
    final b2 = ChessBoard.fromMoves(['f2f3', 'e7e5', 'g2g4']);
    expect(
      ChessBoard.targets(b2, ChessBoard.sq('d8')),
      contains(ChessBoard.sq('h4')),
    );
    // and from h4 the queen can capture the white king on e1
    final b3 = ChessBoard.fromMoves(['f2f3', 'e7e5', 'g2g4', 'd8h4', 'a2a3']);
    expect(
      ChessBoard.targets(b3, ChessBoard.sq('h4')),
      contains(ChessBoard.sq('e1')),
    );
  });

  test('kings move one square, cannot capture own piece', () {
    final b = ChessBoard.initial();
    expect(ChessBoard.targets(b, ChessBoard.sq('e1')), isEmpty);
    final b2 = ChessBoard.fromMoves(['e2e4', 'd7d5']);
    expect(ChessBoard.targets(b2, ChessBoard.sq('e1')), [ChessBoard.sq('e2')]);
  });

  test('illegal moves are rejected by targets', () {
    final b = ChessBoard.initial();
    expect(ChessBoard.targets(b, ChessBoard.sq('e2')),
        isNot(contains(ChessBoard.sq('e5'))));
    expect(ChessBoard.targets(b, ChessBoard.sq('a1')), isEmpty);
  });
}
