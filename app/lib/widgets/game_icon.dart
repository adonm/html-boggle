/// Per-game icons used by the picker, the lobby showcase, and the guide.
library;

import 'package:flutter/material.dart';

import '../games/game_logic.dart';
import 'chess_piece.dart';

Widget gameIcon(GameMode m, {double size = 20}) => switch (m) {
      GameMode.boggle => Icon(Icons.casino, size: size),
      GameMode.scattergories => Icon(Icons.abc, size: size),
      GameMode.sketchit => Icon(Icons.brush, size: size),
      GameMode.chess => ChessPiece(piece: 'N', white: false, size: size),
      GameMode.go => Icon(Icons.trip_origin, size: size * 0.95),
      GameMode.wordtiles => Icon(Icons.view_module, size: size),
    };
