/// Shared base for replicated-log games (Chess, Go, Word Tiles):
/// seats pinned at round start, turn derived from the log, sticky winner,
/// monotonic log adoption, and the common end-of-game flow. Also the tiny
/// state-merge helpers the other games use for snapshot adoption.
library;

import 'game_logic.dart';

/// Adopt [incoming] only when it's a non-empty string.
String adoptNonEmpty(String current, Object? incoming) =>
    incoming is String && incoming.isNotEmpty ? incoming : current;

/// Sticky bool: once true it stays true until the round resets it.
bool adoptStickyBool(bool current, Object? incoming) =>
    current || incoming == true;

/// A game whose state is a replicated, append-only move log. Every client
/// validates + appends moves deterministically, so the logs converge; host
/// snapshots may be stale, so adoption keeps the longer log and never
/// regresses the winner or seats.
abstract class TurnGameLogic<T> extends GameLogic {
  TurnGameLogic(super.host);

  final List<T> moves = [];
  String winner = '';
  List<String> seats = [];

  /// Whose turn it is, derived from the log.
  String get turnId;

  @override
  bool get isMyTurn => host.meId.isNotEmpty && host.meId == turnId;

  /// Pin the first [count] players (by canonical id order) as seats and
  /// give the round a long deadline (turn games end by rules, not timer).
  void pinSeats(int count) {
    final s = host.sortedPlayers;
    seats = [for (var i = 0; i < count && i < s.length; i++) s[i].id];
    host.deadline = DateTime.now().add(const Duration(hours: 1));
  }

  /// Seat everyone (Word Tiles: the whole room plays).
  void seatAll() {
    seats = [for (final p in host.sortedPlayers) p.id];
    host.deadline = DateTime.now().add(const Duration(hours: 1));
  }

  /// End the game: sticky winner, +1 for the winner, round ends.
  void finish(String winnerLabel, {String? winnerId}) {
    winner = winnerLabel;
    if (winnerId != null && winnerId.isNotEmpty) {
      host.addScore(winnerId, 1);
      host.sfx('win');
    }
    host.endRound();
    host.showToast('Game over!');
  }

  /// Adopt a log from a snapshot - never truncate the local one.
  void adoptLonger(List<dynamic> incoming) {
    if (incoming.length >= moves.length) {
      moves
        ..clear()
        ..addAll(incoming.cast<T>());
    }
  }

  /// Sticky winner adoption.
  void adoptWinner(Object? incoming) {
    if (incoming is String && incoming.isNotEmpty && winner.isEmpty) {
      winner = incoming;
    }
  }

  /// Seats are only replaced by a non-empty snapshot.
  void adoptSeats(List<String>? incoming) {
    if (incoming != null && incoming.isNotEmpty) seats = incoming;
  }

  @override
  void reset() {
    moves.clear();
    winner = '';
    seats = [];
  }
}
