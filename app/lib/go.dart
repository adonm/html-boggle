/// 9x9 Go: stones, captures, suicide ban, simple ko, area scoring.
///
/// Board is 81 chars ('.', 'B', 'W'), index 0 = top-left. Coordinates are
/// standard Go notation: "a1" = bottom-left, "i9" = top-right. A game is a
/// replicated log of moves ("a1", "pass", ...) - black always moves first,
/// so the color of each move is its index parity. Every client replays the
/// log deterministically; validation only needs the board *before* the
/// opponent's previous move for the simple-ko check.
library;

class GoGame {
  static const int size = 9;

  /// "a1".."i9" -> board index, or -1 if malformed.
  static int sq(String coord) {
    if (coord.length < 2) return -1;
    final col = coord.codeUnitAt(0) - 97;
    final row = coord.codeUnitAt(1) - 49;
    if (col < 0 || col > 8 || row < 0 || row > 8) return -1;
    return (8 - row) * 9 + col;
  }

  static String coord(int idx) =>
      '${String.fromCharCode(97 + idx % 9)}${9 - idx ~/ 9}';

  static List<int> neighbors(int idx) {
    final r = idx ~/ 9, c = idx % 9;
    final out = <int>[];
    if (r > 0) out.add(idx - 9);
    if (r < 8) out.add(idx + 9);
    if (c > 0) out.add(idx - 1);
    if (c < 8) out.add(idx + 1);
    return out;
  }

  /// The connected same-color group containing [idx].
  static Set<int> group(List<String> b, int idx) {
    final color = b[idx];
    final seen = <int>{idx};
    final stack = <int>[idx];
    while (stack.isNotEmpty) {
      final cur = stack.removeLast();
      for (final n in neighbors(cur)) {
        if (b[n] == color && seen.add(n)) stack.add(n);
      }
    }
    return seen;
  }

  static bool hasLiberty(List<String> b, Set<int> g) =>
      g.any((i) => neighbors(i).any((n) => b[n] == '.'));

  /// Attempt to place a stone. Returns the resulting board, or null when the
  /// move is illegal (occupied, suicide, or simple ko).
  /// [prev] is the board before the opponent's last move.
  static List<String>? apply(List<String> b, List<String> prev, int idx,
      bool black) {
    if (idx < 0 || idx >= 81 || b[idx] != '.') return null;
    final nb = List.of(b);
    nb[idx] = black ? 'B' : 'W';
    final enemy = black ? 'W' : 'B';
    // capture surrounded enemy groups first
    for (final n in neighbors(idx)) {
      if (nb[n] != enemy) continue;
      final g = group(nb, n);
      if (!hasLiberty(nb, g)) {
        for (final i in g) {
          nb[i] = '.';
        }
      }
    }
    // suicide: own group must have a liberty after captures
    final own = group(nb, idx);
    if (!hasLiberty(nb, own)) return null;
    // simple ko: may not recreate the board position just before the
    // opponent's last move
    if (_eq(nb, prev)) return null;
    return nb;
  }

  static bool _eq(List<String> a, List<String> b) {
    for (var i = 0; i < 81; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  /// Replay a move log. Returns the current board and the board before the
  /// last stone move (for ko checks on the next validation).
  static ({List<String> board, List<String> prev}) replay(List<String> moves) {
    var b = List.filled(81, '.');
    var prev = List.of(b);
    for (var i = 0; i < moves.length; i++) {
      final m = moves[i];
      if (m == 'pass' || m == 'resign') {
        prev = List.of(b);
        continue;
      }
      final idx = sq(m);
      if (idx < 0) continue;
      final nb = apply(b, prev, idx, i.isEven);
      if (nb == null) continue; // invalid entries ignored (never sent)
      prev = List.of(b);
      b = nb;
    }
    return (board: b, prev: prev);
  }

  /// Every legal placement for [black] on [b].
  static List<int> legalMoves(List<String> b, List<String> prev, bool black) {
    final out = <int>[];
    for (var i = 0; i < 81; i++) {
      if (b[i] == '.' && apply(b, prev, i, black) != null) out.add(i);
    }
    return out;
  }

  /// Area score: stones + empty points fully surrounded by one color.
  static ({int black, int white}) score(List<String> b) {
    var black = 0, white = 0;
    for (final c in b) {
      if (c == 'B') black++;
      if (c == 'W') white++;
    }
    final seen = List.filled(81, false);
    for (var i = 0; i < 81; i++) {
      if (b[i] != '.' || seen[i]) continue;
      // flood fill the empty region, tracking bordering colors
      final region = <int>[];
      final stack = <int>[i];
      seen[i] = true;
      final borders = <String>{};
      while (stack.isNotEmpty) {
        final cur = stack.removeLast();
        region.add(cur);
        for (final n in neighbors(cur)) {
          if (b[n] == '.') {
            if (!seen[n]) {
              seen[n] = true;
              stack.add(n);
            }
          } else {
            borders.add(b[n]);
          }
        }
      }
      if (borders.length == 1) {
        if (borders.first == 'B') {
          black += region.length;
        } else {
          white += region.length;
        }
      }
    }
    return (black: black, white: white);
  }
}
