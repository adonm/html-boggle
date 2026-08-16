/// Word Tiles: scrabble-style crossword on an 11x11 board.
///
/// A game is a replicated log of moves plus a bag order served by the round
/// starter, so every client derives racks, board, and scores deterministically:
/// seats draw 7 tiles in seat order, then refill to 7 from the bag after each
/// of their moves. Validation rules:
///   - tiles all in one row or column, contiguous (no gaps), on empty squares
///   - the first play must cover the center star (double word); later plays
///     must touch an existing tile
///   - every formed word (main + perpendicular crosses) is 2+ letters and in
///     the dictionary
///   - scoring: sum of letter values of every formed word; +50 for a 7-tile
///     play; the opening play is doubled.
library;

class WtGame {
  static const int size = 11;
  static const int center = 5;

  /// Classic English Scrabble values.
  static const Map<String, int> values = {
    'A': 1, 'B': 3, 'C': 3, 'D': 2, 'E': 1, 'F': 4, 'G': 2, 'H': 4,
    'I': 1, 'J': 8, 'K': 5, 'L': 1, 'M': 3, 'N': 1, 'O': 1, 'P': 3,
    'Q': 10, 'R': 1, 'S': 1, 'T': 1, 'U': 1, 'V': 4, 'W': 4, 'X': 8,
    'Y': 4, 'Z': 10,
  };

  /// Classic English tile distribution (blanks excluded).
  static const String distribution = 'EEEEEEEEEEEEAAAAAAAAAIIIIIIIIIOOOOOOOO'
      'NNNNNNRRRRRRTTTTTTLLLLSSSSUUUUDDDDGGGBBCCMMPPFFHHVVWWYYKJXQZ';

  static List<String> shuffledBag() {
    final bag = distribution.split('')..shuffle();
    return bag;
  }

  /// Board from a replicated move log: entries are 'pass' or a list of
  /// [x, y, letter] triples. Returns {x:y -> letter}.
  static Map<String, String> boardFromMoves(List<dynamic> moves) {
    final board = <String, String>{};
    for (final m in moves) {
      if (m is! List) continue;
      for (final t in m) {
        final x = (t[0] as num).toInt();
        final y = (t[1] as num).toInt();
        board['$x:$y'] = (t[2] as String).toUpperCase();
      }
    }
    return board;
  }

  static bool inBounds(int x, int y) =>
      x >= 0 && x < size && y >= 0 && y < size;

  /// Validate + score a play. Returns null when valid with the score, or an
  /// error string. [tiles] is [[x, y, letter], ...]; letters are uppercase.
  static String? validate({
    required Map<String, String> board,
    required List<String> rack,
    required List<List<dynamic>> tiles,
    required bool Function(String) hasWord,
  }) {
    if (tiles.isEmpty || tiles.length > 7) return 'play 1-7 tiles';
    final rackLeft = List.of(rack);
    final placed = <List<dynamic>>[];
    for (final t in tiles) {
      final x = (t[0] as num).toInt();
      final y = (t[1] as num).toInt();
      final ch = (t[2] as String).toUpperCase();
      if (!inBounds(x, y)) return 'off the board';
      if (board.containsKey('$x:$y')) return 'square is occupied';
      if (!rackLeft.remove(ch)) return '"$ch" is not in your rack';
      placed.add([x, y, ch]);
    }
    final sameRow = placed.every((p) => p[0] == placed[0][0]);
    final sameCol = placed.every((p) => p[1] == placed[0][1]);
    if (!sameRow && !sameCol) return 'tiles must be in one row or column';
    placed.sort((a, b) => sameRow
        ? (a[1] as int).compareTo(b[1] as int)
        : (a[0] as int).compareTo(b[0] as int));
    // contiguity: no empty gaps along the line (board tiles bridge the gap)
    final line = <int>[];
    for (final p in placed) {
      line.add((p[sameRow ? 1 : 0] as int));
    }
    final minV = line.reduce((a, b) => a < b ? a : b);
    final maxV = line.reduce((a, b) => a > b ? a : b);
    for (var v = minV; v <= maxV; v++) {
      final key = sameRow ? '${placed[0][0]}:$v' : '$v:${placed[0][1]}';
      if (!board.containsKey(key) && !line.contains(v)) {
        return 'tiles must be connected';
      }
    }
    final isEmpty = board.isEmpty;
    if (isEmpty) {
      if (!placed.any((p) => p[0] == center && p[1] == center)) {
        return 'first play must cover the center star';
      }
    } else {
      final touches = placed.any((p) {
        final x = p[0] as int, y = p[1] as int;
        return board.containsKey('${x + 1}:$y') ||
            board.containsKey('${x - 1}:$y') ||
            board.containsKey('$x:${y + 1}') ||
            board.containsKey('$x:${y - 1}');
      });
      if (!touches) return 'play must connect to existing tiles';
    }

    // rebuild the line word (placed + existing extensions)
    final lineWord = _readWord(board, placed, sameRow);
    final words = [lineWord];
    // perpendicular cross words for each placed tile
    for (final p in placed) {
      final cross = _readWord(board, [p], !sameRow);
      if (cross.length >= 2) words.add(cross);
    }
    for (final w in words) {
      if (w.length < 2) return '"$w" is too short (2+ letters)';
      if (!hasWord(w.toLowerCase())) return '"$w" is not a dictionary word';
    }
    return null;
  }

  /// The words formed by a (valid) play: the line word plus perpendicular
  /// crosses. Used for scoring replays.
  static List<String> formedWords(
      Map<String, String> board, List<List<dynamic>> tiles) {
    if (tiles.isEmpty) return const [];
    final placed = [
      for (final t in tiles)
        [(t[0] as num).toInt(), (t[1] as num).toInt(), (t[2] as String).toUpperCase()],
    ];
    final sameRow = placed.every((p) => p[0] == placed[0][0]);
    final words = <String>[_readWord(board, placed, sameRow)];
    for (final p in placed) {
      final cross = _readWord(board, [p], !sameRow);
      if (cross.length >= 2) words.add(cross);
    }
    return words;
  }

  /// Read the full word along the line of [placed] tiles, extending over
  /// existing board letters. [horizontal] selects the axis.
  static String _readWord(
      Map<String, String> board, List<List<dynamic>> placed, bool horizontal) {
    final axis = horizontal ? 1 : 0;
    final fixed = placed[0][horizontal ? 0 : 1] as int;
    final pos = placed.map((p) => p[axis] as int).toSet();
    var min = pos.reduce((a, b) => a < b ? a : b);
    var max = pos.reduce((a, b) => a > b ? a : b);
    String key(int v) =>
        horizontal ? '$fixed:$v' : '$v:$fixed';
    while (board.containsKey(key(min - 1))) {
      min--;
    }
    while (board.containsKey(key(max + 1))) {
      max++;
    }
    final buf = StringBuffer();
    for (var v = min; v <= max; v++) {
      buf.write(board[key(v)] ?? _placedLetter(placed, axis, v));
    }
    return buf.toString();
  }

  static String _placedLetter(
      List<List<dynamic>> placed, int axis, int v) {
    for (final p in placed) {
      if ((p[axis] as int) == v) return p[2] as String;
    }
    return '?';
  }

  /// Score of the words formed by this play (letter values, double for the
  /// opening play, +50 for using all 7 tiles).
  static int scoreWords(
      List<String> words, {required bool opening, required int tileCount}) {
    var score = 0;
    for (final w in words) {
      for (final ch in w.split('')) {
        score += values[ch] ?? 0;
      }
    }
    if (opening) score *= 2;
    if (tileCount == 7) score += 50;
    return score;
  }
}
