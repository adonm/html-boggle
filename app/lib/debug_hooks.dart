/// Test/debug hooks installed on `window` for the e2e harness.
library;

import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'game.dart';

@JS('window')
external JSObject get _window;

void installDebugHooks(Game game) {
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
      game.boggle?.debugSubmit(word.toDart);
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
      game.scatter?.submit(word.toDart);
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
      game.sketch?.guess(text.toDart);
    }).toJS,
  );
  _window.setProperty(
    '__boggleDebugChessMove'.toJS,
    ((JSString from, JSString to) {
      game.chess?.tryMove(from.toDart, to.toDart);
    }).toJS,
  );
  _window.setProperty(
    '__boggleDebugGoMove'.toJS,
    ((JSString coord) {
      game.go?.tryMove(coord.toDart);
    }).toJS,
  );
  _window.setProperty(
    '__boggleDebugGoPass'.toJS,
    ((JSAny _) {
      game.go?.passTurn();
    }).toJS,
  );
  _window.setProperty(
    '__boggleDebugWtPlay'.toJS,
    ((JSString tilesJson) {
      final raw = jsonDecode(tilesJson.toDart);
      if (raw is List) {
        game.wt?.tryPlay([for (final t in raw) if (t is List) t]);
      }
    }).toJS,
  );
  _window.setProperty(
    '__boggleDebugWtPass'.toJS,
    ((JSAny _) {
      game.wt?.passTurn();
    }).toJS,
  );
}
