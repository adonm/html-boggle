/// Word Tiles: scrabble-style crossword on an 11x11 board. The round starter
/// serves the whole bag order, so racks and scores derive deterministically
/// on every client from bag + replicated move log.
library;

import '../wordtiles.dart';
import 'game_logic.dart';

class WtLogic extends GameLogic {
  WtLogic(super.host);

  @override
  String get wireName => 'wordtiles';

  final List<dynamic> moves = [];
  List<String> bag = [];
  List<String> seats = [];
  String winner = '';

  @override
  bool get needsTwoPlayers => true;

  @override
  String get startToast => 'Round ${host.round} - first play covers the star';

  @override
  void populateStart(Map<String, dynamic> msg) {
    moves.clear();
    winner = '';
    seats = [for (final p in host.sortedPlayers) p.id];
    bag = WtGame.shuffledBag();
    host.deadline = DateTime.now().add(const Duration(hours: 1));
    msg['bag'] = bag.join('');
    msg['seats'] = seats;
  }

  @override
  void applyStart(Map<String, dynamic> m) {
    moves.clear();
    winner = '';
    final b = (m['bag'] as String?) ?? '';
    if (b.isNotEmpty) bag = b.split('');
    final s = m['seats'];
    if (s is List) {
      seats = [for (final seat in s) if (seat is String) seat];
    }
  }

  String get turnId =>
      seats.isEmpty ? '' : seats[moves.length % seats.length];
  @override
  bool get isMyTurn => host.meId == turnId;

  @override
  void onMessage(String type, Map<String, dynamic> m, String from) {
    switch (type) {
      case 'wtMove':
        if (host.phase != Phase.play) return;
        _applyMove(m, from);
      case 'wtPass':
        if (host.phase != Phase.play) return;
        _applyPass(from);
    }
  }

  @override
  Map<String, dynamic> stateJson() => {
        'wtMoves': moves,
        'wtBag': bag.join(''),
        'wtSeats': seats,
        'wtWinner': winner,
      };

  @override
  void adoptState(Map<String, dynamic> m) {
    final wm = m['wtMoves'];
    if (wm is List && wm.length >= moves.length) {
      moves
        ..clear()
        ..addAll(wm);
    }
    final wb = m['wtBag'];
    if (wb is String && wb.isNotEmpty) bag = wb.split('');
    final wseats = m['wtSeats'];
    if (wseats is List && wseats.isNotEmpty) {
      seats = [for (final s in wseats) if (s is String) s];
    }
    final ww = m['wtWinner'];
    if (ww is String && ww.isNotEmpty && winner.isEmpty) winner = ww;
  }

  @override
  Map<String, dynamic> debugJson() => {
        'wtMoves': moves.length,
        'wtWinner': winner,
        'wtSeats': seats,
        'wtMyRack': myRack.join(','),
        'wtMyScore': myScore,
        'wtScores': {
          for (var i = 0; i < seats.length; i++) seats[i]: scoreOf(i),
        },
      };

  @override
  void reset() {
    moves.clear();
    bag = [];
    seats = [];
    winner = '';
  }

  // ------------------------------------------------------------- derivation

  /// Derived board: {x:y -> letter} from the replicated move log.
  Map<String, String> get board => WtGame.boardFromMoves(moves);

  /// Derived rack for a seat: initial 7 in seat order, refill to 7 after
  /// each of that seat's moves. Deterministic from bag + move log.
  List<String> rackOf(int seatIdx) {
    if (bag.isEmpty) return const [];
    var bagIdx = 0;
    final racks = List.generate(seats.length, (_) => <String>[]);
    for (var i = 0; i < seats.length; i++) {
      final n = bag.length - bagIdx;
      final take = n < 7 ? n : 7;
      racks[i].addAll(bag.sublist(bagIdx, bagIdx + take));
      bagIdx += take;
    }
    for (var t = 0; t < moves.length; t++) {
      final seat = t % seats.length;
      final mv = moves[t];
      if (mv is List) {
        for (final tile in mv) {
          racks[seat].remove((tile[2] as String).toUpperCase());
        }
        while (racks[seat].length < 7 && bagIdx < bag.length) {
          racks[seat].add(bag[bagIdx++]);
        }
      }
    }
    return racks[seatIdx];
  }

  List<String> get myRack {
    final i = seats.indexOf(host.meId);
    return i < 0 ? const [] : rackOf(i);
  }

  /// Derived score for a seat: replay the log, scoring each play.
  int scoreOf(int seatIdx) {
    var score = 0;
    var b = <String, String>{};
    for (var t = 0; t < moves.length; t++) {
      final mv = moves[t];
      if (mv is! List) continue;
      final seat = t % seats.length;
      final tiles = <List<dynamic>>[
        for (final tile in mv)
          [
            (tile[0] as num).toInt(),
            (tile[1] as num).toInt(),
            (tile[2] as String).toUpperCase(),
          ],
      ];
      final opening = b.isEmpty;
      final words = WtGame.formedWords(b, tiles);
      if (seat == seatIdx) {
        score += WtGame.scoreWords(
          words,
          opening: opening,
          tileCount: tiles.length,
        );
      }
      for (final t in tiles) {
        b['${t[0]}:${t[1]}'] = t[2] as String;
      }
    }
    return score;
  }

  int get myScore {
    final i = seats.indexOf(host.meId);
    return i < 0 ? 0 : scoreOf(i);
  }

  // ------------------------------------------------------------------ moves

  /// Current player: play tiles [[x, y, letter], ...].
  bool tryPlay(List<List<dynamic>> tiles) {
    if (host.phase != Phase.play) return false;
    if (winner.isNotEmpty || host.meId != turnId) return false;
    final err = WtGame.validate(
      board: board,
      rack: myRack,
      tiles: tiles,
      hasWord: host.finder.hasWord,
    );
    if (err != null) {
      host.showToast(err);
      return false;
    }
    final wire = [
      for (final t in tiles)
        [
          (t[0] as num).toInt(),
          (t[1] as num).toInt(),
          (t[2] as String).toUpperCase(),
        ],
    ];
    moves.add(wire);
    host.send({'t': 'wtMove', 'node': host.meId, 'tiles': wire});
    _checkEnd();
    host.notifyListeners();
    return true;
  }

  void passTurn() {
    if (host.phase != Phase.play) return;
    if (winner.isNotEmpty || host.meId != turnId) return;
    moves.add('pass');
    host.send({'t': 'wtPass', 'node': host.meId});
    _checkEnd();
    host.notifyListeners();
  }

  void _applyMove(Map<String, dynamic> m, String from) {
    if (winner.isNotEmpty || from != turnId) return;
    final raw = m['tiles'];
    if (raw is! List) return;
    final tiles = <List<dynamic>>[];
    for (final t in raw) {
      if (t is! List || t.length < 3) return;
      if (t[0] is! num || t[1] is! num || t[2] is! String) return;
      tiles.add([(t[0] as num).toInt(), (t[1] as num).toInt(), t[2]]);
    }
    final err = WtGame.validate(
      board: board,
      rack: rackOf(seats.indexOf(from)),
      tiles: tiles,
      hasWord: host.finder.hasWord,
    );
    if (err != null) return;
    moves.add(tiles);
    _checkEnd();
    host.notifyListeners();
  }

  void _applyPass(String from) {
    if (winner.isNotEmpty || from != turnId) return;
    moves.add('pass');
    _checkEnd();
    host.notifyListeners();
  }

  /// End when the bag is empty and a rack empties, or everyone passes in a
  /// row. Highest score wins.
  void _checkEnd() {
    if (winner.isNotEmpty) return;
    // remaining bag size: initial 7 per seat, then refills as moves consume
    var remaining = bag.length;
    for (var i = 0; i < seats.length; i++) {
      remaining = remaining > 7 ? remaining - 7 : 0;
    }
    for (var t = 0; t < moves.length; t++) {
      if (moves[t] is! List || remaining <= 0) continue;
      final seat = t % seats.length;
      var rack = rackOf(seat).length;
      while (rack < 7 && remaining > 0) {
        remaining--;
        rack++;
      }
    }
    final bagEmpty = remaining <= 0;
    var rackEmpty = false;
    for (var i = 0; i < seats.length; i++) {
      if (rackOf(i).isEmpty) rackEmpty = true;
    }
    final allPassed = moves.length >= seats.length &&
        moves.sublist(moves.length - seats.length).every((m) => m == 'pass');
    if (!((bagEmpty && rackEmpty) || allPassed)) return;
    var best = -1;
    var bestSeat = -1;
    var tie = false;
    for (var i = 0; i < seats.length; i++) {
      final s = scoreOf(i);
      if (s > best) {
        best = s;
        bestSeat = i;
        tie = false;
      } else if (s == best) {
        tie = true;
      }
    }
    winner = tie ? 'draw' : seats[bestSeat];
    host.addScore(winner, 1);
    host.endRound();
    host.showToast('Game over!');
  }
}
