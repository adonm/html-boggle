/// Capture Chess: full piece movement, no check/checkmate bookkeeping -
/// capturing the king wins. No castling, no en passant; pawns auto-promote
/// to queens. Two players; everyone else spectates.
library;

/// Board as 64 chars: '.' empty, uppercase = white, lowercase = black.
class ChessBoard {
  static List<String> initial() => [
        'r', 'n', 'b', 'q', 'k', 'b', 'n', 'r',
        'p', 'p', 'p', 'p', 'p', 'p', 'p', 'p',
        '.', '.', '.', '.', '.', '.', '.', '.',
        '.', '.', '.', '.', '.', '.', '.', '.',
        '.', '.', '.', '.', '.', '.', '.', '.',
        '.', '.', '.', '.', '.', '.', '.', '.',
        'P', 'P', 'P', 'P', 'P', 'P', 'P', 'P',
        'R', 'N', 'B', 'Q', 'K', 'B', 'N', 'R',
      ];

  static bool isWhite(String c) => c.codeUnitAt(0) >= 65 && c.codeUnitAt(0) <= 90;

  /// Apply [from] -> [to]; pawns reaching the last rank promote to queens.
  static List<String> apply(List<String> b, int from, int to) {
    final nb = List.of(b);
    var piece = nb[from];
    if (piece == 'P' && to < 8) piece = 'Q';
    if (piece == 'p' && to >= 56) piece = 'q';
    nb[to] = piece;
    nb[from] = '.';
    return nb;
  }

  /// All legal target squares for the piece at [from].
  static List<int> targets(List<String> b, int from) {
    final p = b[from];
    if (p == '.') return const [];
    final white = isWhite(p);
    final r = from ~/ 8, c = from % 8;
    final out = <int>[];

    void slide(List<List<int>> dirs) {
      for (final d in dirs) {
        var nr = r + d[0], nc = c + d[1];
        while (nr >= 0 && nr < 8 && nc >= 0 && nc < 8) {
          final idx = nr * 8 + nc;
          final t = b[idx];
          if (t == '.') {
            out.add(idx);
          } else {
            if (isWhite(t) != white) out.add(idx);
            break;
          }
          nr += d[0];
          nc += d[1];
        }
      }
    }

    final kind = p.toLowerCase();
    switch (kind) {
      case 'p':
        final dir = white ? -1 : 1;
        final startRow = white ? 6 : 1;
        final one = (r + dir) * 8 + c;
        if (one >= 0 && one < 64 && b[one] == '.') {
          out.add(one);
          final two = (r + 2 * dir) * 8 + c;
          if (r == startRow && b[two] == '.') out.add(two);
        }
        for (final dc in [-1, 1]) {
          final nc = c + dc;
          if (nc < 0 || nc > 7) continue;
          final idx = (r + dir) * 8 + nc;
          if (idx < 0 || idx >= 64) continue;
          final t = b[idx];
          if (t != '.' && isWhite(t) != white) out.add(idx);
        }
      case 'n':
        for (final d in const [
          [-2, -1], [-2, 1], [-1, -2], [-1, 2],
          [1, -2], [1, 2], [2, -1], [2, 1],
        ]) {
          final nr = r + d[0], nc = c + d[1];
          if (nr < 0 || nr > 7 || nc < 0 || nc > 7) continue;
          final idx = nr * 8 + nc;
          final t = b[idx];
          if (t == '.' || isWhite(t) != white) out.add(idx);
        }
      case 'b':
        slide(const [[-1, -1], [-1, 1], [1, -1], [1, 1]]);
      case 'r':
        slide(const [[-1, 0], [1, 0], [0, -1], [0, 1]]);
      case 'q':
        slide(const [
          [-1, -1], [-1, 1], [1, -1], [1, 1],
          [-1, 0], [1, 0], [0, -1], [0, 1],
        ]);
      case 'k':
        for (final d in const [
          [-1, -1], [-1, 0], [-1, 1], [0, -1],
          [0, 1], [1, -1], [1, 0], [1, 1],
        ]) {
          final nr = r + d[0], nc = c + d[1];
          if (nr < 0 || nr > 7 || nc < 0 || nc > 7) continue;
          final idx = nr * 8 + nc;
          final t = b[idx];
          if (t == '.' || isWhite(t) != white) out.add(idx);
        }
    }
    return out;
  }

  /// Board resulting from replaying [moves] ("e2e4", "a7a8q").
  static List<String> fromMoves(List<String> moves) {
    var b = initial();
    for (final m in moves) {
      if (m.length < 4) continue;
      final from = sq(m.substring(0, 2));
      final to = sq(m.substring(2, 4));
      if (from < 0 || to < 0 || from >= 64 || to >= 64) continue;
      b = apply(b, from, to);
    }
    return b;
  }

  static int sq(String s) {
    if (s.length < 2) return -1;
    final f = s.codeUnitAt(0) - 97;
    final r = 8 - (s.codeUnitAt(1) - 48);
    if (f < 0 || f > 7 || r < 0 || r > 7) return -1;
    return r * 8 + f;
  }

  static String sqName(int idx) =>
      '${String.fromCharCode(97 + idx % 8)}${8 - idx ~/ 8}';

  static String glyph(String piece) => switch (piece) {
        'K' => '♔', 'Q' => '♕', 'R' => '♖', 'B' => '♗', 'N' => '♘', 'P' => '♙',
        'k' => '♚', 'q' => '♛', 'r' => '♜', 'b' => '♝', 'n' => '♞', 'p' => '♟',
        _ => '',
      };
}
