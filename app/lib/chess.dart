/// Board square helpers for the chess UI: "e2" <-> board index (0 = a8)
/// and piece color. Move legality lives in the `chess` rules engine
/// (see games/chess_logic.dart).
library;

class ChessBoard {
  static int sq(String s) {
    if (s.length < 2) return -1;
    final f = s.codeUnitAt(0) - 97;
    final r = 8 - (s.codeUnitAt(1) - 48);
    if (f < 0 || f > 7 || r < 0 || r > 7) return -1;
    return r * 8 + f;
  }

  static String sqName(int idx) =>
      '${String.fromCharCode(97 + idx % 8)}${8 - idx ~/ 8}';

  static bool isWhite(String c) =>
      c.codeUnitAt(0) >= 65 && c.codeUnitAt(0) <= 90;
}
