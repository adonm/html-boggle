/// Bridge to the iroh gossip layer (Rust wasm, loaded by glue.js).
///
/// Dart drives `window.__boggleGlue` (join/send) and receives gossip events
/// through `window.__boggleToFlutter`, a sink installed here.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:flutter/services.dart';

@JS('window')
external JSObject get _window;

@JS('window.location')
external JSObject get _jsLocation;

@JS('navigator')
external JSObject get _navigator;

/// The full page URL, including the query string.
/// (document.baseURI drops it, so Uri.base can't see ?room= deep links.)
String get pageHref => (_jsLocation.getProperty<JSString>('href'.toJS)).toDart;

/// Share [url] via the native share sheet on platforms that have it (mobile
/// browsers); falls back to copying to the clipboard. Returns true when the
/// native sheet was used.
Future<bool> shareLink({required String title, required String url}) async {
  try {
    final share = _navigator.getProperty<JSAny?>('share'.toJS);
    if (share != null && !share.isUndefinedOrNull) {
      final promise = _navigator.callMethod<JSAny?>(
        'share'.toJS,
        {'title': title, 'url': url}.jsify(),
      ) as JSPromise<JSAny?>;
      await promise.toDart;
      return true;
    }
  } catch (_) {
    /* no Web Share API, or the user dismissed the sheet - fall through */
  }
  await Clipboard.setData(ClipboardData(text: url));
  return false;
}

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
