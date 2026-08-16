import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

import 'game.dart';
import 'screens.dart';
import 'theme.dart';

@JS('window')
external JSObject get _window;

/// Install test/debug hooks on window for the e2e harness.
void _installDebugHooks(Game game) {
  final state = ((JSString _) => jsonEncode(game.debugState()).toJS).toJS;
  _window.setProperty('__boggleDebugState'.toJS, state);
  _window.setProperty(
    '__boggleDebugJoin'.toJS,
    ((JSString room, JSString name) {
      game.join(roomCode: room.toDart, name: name.toDart);
    }).toJS,
  );
  _window.setProperty(
    '__boggleDebugSubmit'.toJS,
    ((JSString word) {
      game.debugSubmit(word.toDart);
    }).toJS,
  );
  _window.setProperty(
    '__boggleDebugStart'.toJS,
    ((JSAny _) {
      game.startRound();
    }).toJS,
  );
  _window.setProperty(
    '__boggleDebugReady'.toJS,
    ((JSAny _) {
      game.toggleReady();
    }).toJS,
  );
  _window.setProperty(
    '__boggleDebugSubmitScat'.toJS,
    ((JSString word) {
      game.submitScattergories(word.toDart);
    }).toJS,
  );
  _window.setProperty(
    '__boggleDebugEndRound'.toJS,
    ((JSAny _) {
      game.debugEndRound();
    }).toJS,
  );
  _window.setProperty(
    '__boggleDebugSetMode'.toJS,
    ((JSString mode) {
      game.debugSetMode(mode.toDart);
    }).toJS,
  );
  _window.setProperty(
    '__boggleDebugGuess'.toJS,
    ((JSString text) {
      game.sketchGuess(text.toDart);
    }).toJS,
  );
  _window.setProperty(
    '__boggleDebugChessMove'.toJS,
    ((JSString from, JSString to) {
      game.chessTryMove(from.toDart, to.toDart);
    }).toJS,
  );
  _window.setProperty(
    '__boggleDebugGoMove'.toJS,
    ((JSString coord) {
      game.goTryMove(coord.toDart);
    }).toJS,
  );
  _window.setProperty(
    '__boggleDebugGoPass'.toJS,
    ((JSAny _) {
      game.goPassTurn();
    }).toJS,
  );
  _window.setProperty(
    '__boggleDebugWtPlay'.toJS,
    ((JSString tilesJson) {
      final raw = jsonDecode(tilesJson.toDart);
      if (raw is List) {
        game.wtTryPlay([for (final t in raw) if (t is List) t]);
      }
    }).toJS,
  );
  _window.setProperty(
    '__boggleDebugWtPass'.toJS,
    ((JSAny _) {
      game.wtPassTurn();
    }).toJS,
  );
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Real semantics DOM: screen readers and tests can navigate the app.
  SemanticsBinding.instance.ensureSemantics();

  final game = Game();
  await game.init();
  _installDebugHooks(game);

  final themes = ThemeController.instance;

  runApp(
    ListenableBuilder(
      listenable: themes,
      builder: (context, _) => MaterialApp(
        title: 'Boggle',
        debugShowCheckedModeBanner: false,
        theme: themes.themeData,
        home: HomeScreen(game: game),
      ),
    ),
  );
}
