// lib/narrate_web_audio.dart
// JS interop bindings for Web Audio / MediaRecorder APIs.
// Uses dart:js_interop (NOT deprecated dart:js / package:js).

// ignore_for_file: avoid_web_libraries_in_flutter

@JS()
library;

import 'dart:js_interop';

@JS('navigator.mediaDevices.getUserMedia')
external JSPromise getUserMedia(JSAny constraints);

extension type MediaRecorder._(JSObject _) implements JSObject {
  @JS('MediaRecorder')
  external factory MediaRecorder(JSAny stream, JSAny options);

  external void start(int timeslice);
  external void stop();
  external String get state;

  @JS('ondataavailable')
  external set onDataAvailable(JSFunction fn);
}

// Phase 4.0.7.6 — needed to fully release the mic on stop. Without calling
// stop() on each track, the browser keeps the recording indicator on and
// the audio device pinned even after the WebSocket and MediaRecorder are
// torn down.
extension type MediaStream._(JSObject _) implements JSObject {
  external JSArray<MediaStreamTrack> getTracks();
}

extension type MediaStreamTrack._(JSObject _) implements JSObject {
  external void stop();
}

extension type BlobEvent._(JSObject _) implements JSObject {
  external JSAny get data;
}

extension type FileReader._(JSObject _) implements JSObject {
  @JS('FileReader')
  external factory FileReader();

  external void readAsArrayBuffer(JSAny blob);

  @JS('onloadend')
  external set onLoadEnd(JSFunction fn);

  external JSAny get result;
}
