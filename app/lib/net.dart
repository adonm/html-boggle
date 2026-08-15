/// Bridge to the iroh gossip layer (Rust wasm, loaded by glue.js).
///
/// Dart drives `window.__boggleGlue` (join/send) and receives gossip events
/// through `window.__boggleToFlutter`, a sink installed here.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

@JS('window')
external JSObject get _window;

class NetBridge {
  NetBridge._();

  static final NetBridge instance = NetBridge._();

  final StreamController<Map<String, dynamic>> _events = StreamController.broadcast();
  Stream<Map<String, dynamic>> get events => _events.stream;

  bool _registered = false;

  /// Install the JS-side event sink (glue.js calls it with JSON strings).
  void registerEventSink() {
    if (_registered) return;
    _registered = true;
    _window.setProperty(
      '__boggleToFlutter'.toJS,
      ((JSString json) {
        try {
          final decoded = jsonDecode(json.toDart);
          if (decoded is Map<String, dynamic>) _events.add(decoded);
        } catch (_) {
          /* ignore malformed events */
        }
      }).toJS,
    );
  }

  JSObject get _glue => _window.getProperty<JSObject>('__boggleGlue'.toJS);

  /// Join a room's gossip topic. Resolves with our node id.
  Future<String> join({
    required String room,
    required String topicHex,
    required String name,
  }) async {
    final promise = _glue.callMethod<JSAny>(
      'join'.toJS,
      room.toJS,
      topicHex.toJS,
      name.toJS,
    ) as JSPromise<JSAny?>;
    final value = await promise.toDart;
    return (value as JSString).toDart;
  }

  /// Broadcast a JSON app message (fire and forget).
  void send(String json) {
    _glue.callMethod<JSAny?>('send'.toJS, json.toJS);
  }
}
