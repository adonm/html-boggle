/// Chess pieces from the chess_vectors_flutter package (MIT): the classic
/// Wikimedia-Commons vector set as Flutter widgets, with per-piece fill
/// and stroke colors.
library;

import 'package:chess_vectors_flutter/chess_vectors_flutter.dart';
import 'package:flutter/material.dart';

class ChessPiece extends StatelessWidget {
  const ChessPiece({
    super.key,
    required this.piece,
    required this.white,
    this.size = 52,
  });

  /// 'P','N','B','R','Q','K' (case irrelevant).
  final String piece;
  final bool white;
  final double size;

  static const Color whiteFill = Color(0xFFF8F6F0);
  static const Color whiteStroke = Color(0xFF3A352F);
  static const Color blackFill = Color(0xFF1C1917);
  static const Color blackStroke = Color(0xFF57534E);

  @override
  Widget build(BuildContext context) {
    final fill = white ? whiteFill : blackFill;
    final stroke = white ? whiteStroke : blackStroke;
    return switch (piece.toUpperCase()) {
      'K' => white
          ? WhiteKing(size: size, fillColor: fill, strokeColor: stroke)
          : BlackKing(size: size, fillColor: fill, strokeColor: stroke),
      'Q' => white
          ? WhiteQueen(size: size, fillColor: fill, strokeColor: stroke)
          : BlackQueen(size: size, fillColor: fill, strokeColor: stroke),
      'R' => white
          ? WhiteRook(size: size, fillColor: fill, strokeColor: stroke)
          : BlackRook(size: size, fillColor: fill, strokeColor: stroke),
      'B' => white
          ? WhiteBishop(size: size, fillColor: fill, strokeColor: stroke)
          : BlackBishop(size: size, fillColor: fill, strokeColor: stroke),
      'N' => white
          ? WhiteKnight(size: size, fillColor: fill, strokeColor: stroke)
          : BlackKnight(size: size, fillColor: fill, strokeColor: stroke),
      _ => white
          ? WhitePawn(size: size, fillColor: fill, strokeColor: stroke)
          : BlackPawn(size: size, fillColor: fill, strokeColor: stroke),
    };
  }
}
