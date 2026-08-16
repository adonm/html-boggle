import 'package:boggle_app/wordtiles.dart';
import 'package:flutter_test/flutter_test.dart';

/// Tiny fake dictionary: uppercase words.
bool hasWord(String w) => {'cat', 'cats', 'bat', 'cot', 'rat', 'art', 'acts',
  'to', 'scat'}.contains(w) || w.length >= 3;

void main() {
  test('opening play must cover the center', () {
    final err = WtGame.validate(
      board: {},
      rack: ['C', 'A', 'T'],
      tiles: [
        [0, 0, 'C'],
        [0, 1, 'A'],
        [0, 2, 'T'],
      ],
      hasWord: (w) => true,
    );
    expect(err, 'first play must cover the center star');
  });

  test('opening play through the center scores double', () {
    final err = WtGame.validate(
      board: {},
      rack: ['C', 'A', 'T'],
      tiles: [
        [5, 5, 'C'],
        [5, 6, 'A'],
        [5, 7, 'T'],
      ],
      hasWord: hasWord,
    );
    expect(err, isNull);
    final score = WtGame.scoreWords(
      ['CAT'],
      opening: true,
      tileCount: 3,
    );
    expect(score, (1 + 3 + 1) * 2);
  });

  test('tiles must be contiguous and match the rack', () {
    final board = {'5:5': 'C'};
    // gap between the two placed tiles
    expect(
      WtGame.validate(
        board: board,
        rack: ['A', 'T'],
        tiles: [
          [5, 6, 'A'],
          [5, 8, 'T'],
        ],
        hasWord: (w) => true,
      ),
      'tiles must be connected',
    );
    // letter not in rack
    expect(
      WtGame.validate(
        board: board,
        rack: ['A', 'T'],
        tiles: [
          [5, 6, 'Z'],
        ],
        hasWord: (w) => true,
      ),
      '"Z" is not in your rack',
    );
    // occupied square
    expect(
      WtGame.validate(
        board: board,
        rack: ['A', 'T'],
        tiles: [
          [5, 5, 'A'],
        ],
        hasWord: (w) => true,
      ),
      'square is occupied',
    );
  });

  test('crossword play validates the formed words', () {
    // existing: C A T vertical at x=5 (y=5,6,7)
    final board = {'5:5': 'C', '5:6': 'A', '5:7': 'T'};
    // play B A T horizontally through the A at (5,6): forms CAT + BAT
    final err = WtGame.validate(
      board: board,
      rack: ['B', 'A', 'T'],
      tiles: [
        [4, 6, 'B'],
        [6, 6, 'T'],
      ],
      hasWord: hasWord,
    );
    expect(err, isNull);
    // and both words score (letters counted per word)
    final score = WtGame.scoreWords(['BAT', 'CAT'], opening: false, tileCount: 2);
    expect(score, (3 + 1 + 1) + (3 + 1 + 1));
  });

  test('two-letter line and cross words are legal', () {
    // existing A at (5,6); play T O vertically at x=4 -> line TO + cross TA
    final board = {'5:6': 'A'};
    final tiles = [
      [4, 6, 'T'],
      [4, 7, 'O'],
    ];
    final err = WtGame.validate(
      board: board,
      rack: ['T', 'O'],
      tiles: tiles,
      hasWord: (w) => true,
    );
    expect(err, isNull);
    expect(WtGame.formedWords(board, tiles), ['TO', 'TA']);
  });

  test('bingo bonus for a 7-tile play', () {
    expect(
      WtGame.scoreWords(['AAAAAAA'], opening: false, tileCount: 7),
      7 * 1 + 50,
    );
  });

  test('board replays from the move log', () {
    final b = WtGame.boardFromMoves([
      [
        [5, 5, 'c'],
        [5, 6, 'a'],
        [5, 7, 't'],
      ],
      'pass',
    ]);
    expect(b, {'5:5': 'C', '5:6': 'A', '5:7': 'T'});
  });
}
