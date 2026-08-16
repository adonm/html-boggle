/// Chess: full rules via the pure-Dart `chess` engine - castling, en
/// passant, promotion, checkmate, stalemate, insufficient material,
/// threefold repetition. Seats are pinned at round start so a late
/// spectator can never steal one; every client validates moves against
/// the engine identically, so the replicated logs converge.
library;

import 'package:chess/chess.dart' as cc;

import 'game_logic.dart';
import 'turn_game.dart';

class ChessLogic extends TurnGameLogic<String> {
  ChessLogic(super.host);

  @override
  String get wireName => 'chess';

  @override
  String get startToast => 'Round ${host.round} - white moves first';

  /// White = seats[0], black = seats[1].
  String get white => seats.isEmpty ? '' : seats[0];
  String get black => seats.length < 2 ? '' : seats[1];
  bool get whiteTurn => moves.length.isEven;
  @override
  String get turnId => whiteTurn ? white : black;

  @override
  void populateStart(Map<String, dynamic> msg) {
    moves.clear();
    winner = '';
    pinSeats(2);
    // solo practice: one player sits both sides
    if (host.players.length < 2) seats = [host.meId, host.meId];
    msg['white'] = white;
    msg['black'] = black;
  }

  @override
  void applyStart(Map<String, dynamic> m) {
    moves.clear();
    winner = '';
    seats = [
      (m['white'] as String?) ?? '',
      (m['black'] as String?) ?? '',
    ]..removeWhere((s) => s.isEmpty);
  }

  @override
  void onMessage(String type, Map<String, dynamic> m, String from) {
    if (type != 'chessMove') return;
    if (host.phase != Phase.play) return;
    _applyMove(m, from);
  }

  @override
  Map<String, dynamic> stateJson() => {
        'chessMoves': moves,
        'chessWinner': winner,
        'chessWhite': white,
        'chessBlack': black,
      };

  @override
  void adoptState(Map<String, dynamic> m) {
    final cm = m['chessMoves'];
    if (cm is List) {
      adoptLonger([for (final v in cm) if (v is String) v]);
    }
    adoptWinner(m['chessWinner']);
    final w = adoptNonEmpty(white, m['chessWhite']);
    final b = adoptNonEmpty(black, m['chessBlack']);
    if (w != white || b != black) seats = [w, b];
  }

  @override
  Map<String, dynamic> debugJson() => {
        'chessMoves': moves.join(','),
        'chessWinner': winner,
        'chessWhite': white,
        'chessBlack': black,
      };

  // -------------------------------------------------------------- engine

  /// Replay the log through the rules engine.
  cc.Chess _engine() {
    final g = cc.Chess();
    for (final mv in moves) {
      if (mv.length < 4) break;
      final from = cc.Chess.SQUARES[mv.substring(0, 2)];
      final to = cc.Chess.SQUARES[mv.substring(2, 4)];
      if (from == null || to == null) break;
      final promo = mv.length > 4 ? _promoFrom(mv[4]) : null;
      final legal = g.generate_moves().where((m) =>
          m.from == from &&
          m.to == to &&
          (promo == null ? m.promotion == null : m.promotion == promo));
      if (legal.isEmpty) break;
      g.make_move(legal.first);
    }
    return g;
  }

  static cc.PieceType? _promoFrom(String c) => switch (c.toLowerCase()) {
        'q' => cc.PieceType.QUEEN,
        'r' => cc.PieceType.ROOK,
        'b' => cc.PieceType.BISHOP,
        'n' => cc.PieceType.KNIGHT,
        _ => null,
      };

  static String _promoChar(cc.PieceType p) => switch (p) {
        cc.PieceType.QUEEN => 'q',
        cc.PieceType.ROOK => 'r',
        cc.PieceType.BISHOP => 'b',
        cc.PieceType.KNIGHT => 'n',
        _ => 'q',
      };

  static String _pieceChar(cc.Piece? p) {
    if (p == null) return '.';
    final white = p.color == cc.Color.WHITE;
    return switch (p.type) {
      cc.PieceType.KING => white ? 'K' : 'k',
      cc.PieceType.QUEEN => white ? 'Q' : 'q',
      cc.PieceType.ROOK => white ? 'R' : 'r',
      cc.PieceType.BISHOP => white ? 'B' : 'b',
      cc.PieceType.KNIGHT => white ? 'N' : 'n',
      _ => white ? 'P' : 'p',
    };
  }

  /// Board for rendering: 64 chars (a8=0) from the engine state.
  List<String> get displayBoard {
    final g = _engine();
    return [
      for (var i = 0; i < 64; i++)
        _pieceChar(g.board[(i ~/ 8) * 16 + (i % 8)]),
    ];
  }

  /// True when the side to move is in check.
  bool get isCheck => _engine().in_check;

  /// Legal target square names for the piece on [from] ("e2").
  Set<String> legalTargetsFrom(String from) {
    final sq = cc.Chess.SQUARES[from];
    if (sq == null) return const {};
    return {
      for (final m in _engine().generate_moves())
        if (m.from == sq) m.toAlgebraic,
    };
  }

  /// Promotion piece for a pending from->to move, or null.
  String? promotionFor(String from, String to) {
    final f = cc.Chess.SQUARES[from];
    final t = cc.Chess.SQUARES[to];
    if (f == null || t == null) return null;
    for (final m in _engine().generate_moves()) {
      if (m.from == f && m.to == t && m.promotion != null) {
        return _promoChar(m.promotion!);
      }
    }
    return null;
  }

  // ------------------------------------------------------------------ moves

  /// Current player: attempt a move from-to ("e2", "e4"), with an optional
  /// promotion piece char.
  bool tryMove(String from, String to, {String? promo}) {
    if (host.phase != Phase.play || winner.isNotEmpty) return false;
    if (host.meId != turnId) return false;
    if (!_validate(from, to, promo)) {
      host.showToast('illegal move');
      return false;
    }
    moves.add('$from$to${promo ?? ''}');
    host.send({
      't': 'chessMove',
      'node': host.meId,
      'from': from,
      'to': to,
      if (promo != null) 'promo': promo,
    });
    _checkEnd();
    host.notifyListeners();
    return true;
  }

  void _applyMove(Map<String, dynamic> m, String from) {
    if (winner.isNotEmpty || from != turnId) return;
    final f = (m['from'] as String?) ?? '';
    final t = (m['to'] as String?) ?? '';
    final promo = m['promo'] as String?;
    if (!_validate(f, t, promo)) return;
    moves.add('$f$t${promo ?? ''}');
    _checkEnd();
    host.notifyListeners();
  }

  /// Engine legality: the move must be in the generated legal move list.
  bool _validate(String from, String to, String? promo) {
    final f = cc.Chess.SQUARES[from];
    final t = cc.Chess.SQUARES[to];
    if (f == null || t == null) return false;
    final promoType = promo == null ? null : _promoFrom(promo);
    return _engine().generate_moves().any((m) =>
        m.from == f &&
        m.to == t &&
        (promoType == null ? m.promotion == null : m.promotion == promoType));
  }

  void _checkEnd() {
    final g = _engine();
    if (g.in_checkmate) {
      final moverIsWhite = g.turn == cc.Color.BLACK;
      finish(moverIsWhite ? 'white' : 'black',
          winnerId: moverIsWhite ? white : black);
      host.showToast('Checkmate!');
    } else if (g.in_draw) {
      finish('draw');
      host.showToast('Draw');
    }
  }
}
