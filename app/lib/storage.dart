/// localStorage helpers: the cached room + name (identity persistence is
/// handled in glue.js via the iroh secret key), so reloads can rejoin as
/// the same player.
library;

import 'dart:js_interop';
import 'dart:js_interop_unsafe';

@JS('window.localStorage')
external JSObject get _storage;

String? getStored(String key) {
  try {
    final raw = _storage.callMethod<JSAny?>('getItem'.toJS, key.toJS);
    if (raw != null && !raw.isUndefinedOrNull) return (raw as JSString).toDart;
  } catch (_) {
    /* storage unavailable */
  }
  return null;
}

void setStored(String key, String value) {
  try {
    _storage.callMethod<JSAny?>('setItem'.toJS, key.toJS, value.toJS);
  } catch (_) {
    /* storage unavailable */
  }
}

void removeStored(String key) {
  try {
    _storage.callMethod<JSAny?>('removeItem'.toJS, key.toJS);
  } catch (_) {
    /* storage unavailable */
  }
}

String? get storedRoom => getStored('boggle.room');
String? get storedName => getStored('boggle.name');

/// Remember the current room + player name for auto-rejoin on the next visit.
void persistRoom(String room, String name) {
  setStored('boggle.room', room);
  setStored('boggle.name', name);
}

/// Forget the room (explicit leave); reloads stay in the lobby.
void forgetRoom() => removeStored('boggle.room');
