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

  @JS('ondataavailable')
  external set onDataAvailable(JSFunction fn);
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
