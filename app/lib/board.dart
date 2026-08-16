/// Board generation: the leader deals a random board each round and serves it
/// to everyone in the start message; the deterministic derivation below is
/// only a fallback for old/missing boards.
library;

import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

/// Classic 4x4 Boggle dice set (one die carries "Qu").
const List<String> dice = [
  'AAEEGN', 'ABBJOO', 'ACHOPS', 'AFFKPS',
  'AOOTTW', 'CIMOTU', 'DEILRX', 'DELRVY',
  'DISTTY', 'EEGHNW', 'EEINSU', 'EHRTVW',
  'EIOSST', 'ELRTTY', 'HIMNQU', 'HLNNRZ',
];

/// Deal a fresh random board: shuffle the classic dice and pick a random
/// face per die. "qu" occupies one tile.
List<String> generateBoard(Random rng) {
  final shuffled = List.of(dice)..shuffle(rng);
  return [for (final die in shuffled) die[rng.nextInt(6)].toLowerCase()];
}

/// Deterministic fallback board for a room+round ("qu" occupies one tile).
List<String> deriveBoard(String room, int round) {
  final bytes = sha256.convert(utf8.encode('board:$room:$round')).bytes;
  return [for (var i = 0; i < 16; i++) dice[i][bytes[i] % 6].toLowerCase()];
}
/// iroh gossip topic id (32 bytes, hex) for a room.
String topicHex(String room) => sha256.convert(utf8.encode('topic:$room')).toString();

int scoreForLen(int len) {
  if (len <= 4) return 1;
  if (len == 5) return 2;
  if (len == 6) return 3;
  if (len == 7) return 5;
  return 11;
}

/// Dictionary lookup + path validation against the room board.
class WordFinder {
  WordFinder(List<String> words) : _dict = words;

  /// Sorted word list (2..16 lowercase letters).
  final List<String> _dict;

  List<String> board = const [];
  final List<bool> _visited = List.filled(16, false);

  bool hasWord(String w) {
    var lo = 0, hi = _dict.length - 1;
    while (lo <= hi) {
      final mid = lo + (hi - lo) ~/ 2;
      final cmp = _dict[mid].compareTo(w);
      if (cmp == 0) return true;
      if (cmp < 0) {
        lo = mid + 1;
      } else {
        hi = mid - 1;
      }
    }
    return false;
  }

  /// Can [w] be formed from adjacent tiles (each tile at most once)?
  bool forms(String w) => findPath(w) != null;

  /// Find a valid tile path for [w], or null.
  List<int>? findPath(String w) {
    _visited.fillRange(0, 16, false);
    for (var i = 0; i < 16; i++) {
      final tile = board[i];
      if (tile.isEmpty || w.length < tile.length) continue;
      if (!w.startsWith(tile)) continue;
      _visited[i] = true;
      final path = _dfs(w, tile.length, i, [i]);
      if (path != null) return path;
      _visited[i] = false;
    }
    return null;
  }

  List<int>? _dfs(String w, int idx, int pos, List<int> path) {
    if (idx == w.length) return path;
    final r = pos ~/ 4, c = pos % 4;
    for (var dr = -1; dr <= 1; dr++) {
      for (var dc = -1; dc <= 1; dc++) {
        if (dr == 0 && dc == 0) continue;
        final nr = r + dr, nc = c + dc;
        if (nr < 0 || nr > 3 || nc < 0 || nc > 3) continue;
        final np = nr * 4 + nc;
        if (_visited[np]) continue;
        final tile = board[np];
        if (tile.isEmpty || idx + tile.length > w.length) continue;
        if (!w.startsWith(tile, idx)) continue;
        _visited[np] = true;
        final res = _dfs(w, idx + tile.length, np, [...path, np]);
        if (res != null) return res;
        _visited[np] = false;
      }
    }
    return null;
  }
}
