import 'dart:convert';
import 'dart:async';
import 'dart:js_interop';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// JS binding to the browser's Audio constructor.
@JS('Audio')
extension type _Audio._(JSObject _) implements JSObject {
  external _Audio([JSString? src]);
  external JSPromise<JSAny?> play();
  external void pause();
  external set currentTime(JSNumber value);
  external set onended(JSFunction? handler);
  external set onerror(JSFunction? handler);
}

const String _ttsBaseUrl = String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: 'http://localhost:8000',
);

_Audio? _currentAudio;
VoidCallback? _completionHandler;
VoidCallback? _cancelHandler;

void setTTSCompletionHandler(VoidCallback handler) {
  _completionHandler = handler;
}

void setTTSCancelHandler(VoidCallback handler) {
  _cancelHandler = handler;
}

/// Calls the backend /tts endpoint and plays the returned MP3 audio.
Future<void> speak(String text) async {
  if (text.trim().isEmpty) return;
  await stopSpeaking();

  try {
    final uri = Uri.parse('$_ttsBaseUrl/tts');
    final response = await http
        .post(
          uri,
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'text': text}),
        )
        .timeout(const Duration(seconds: 60));

    if (response.statusCode == 200) {
      final base64Audio = base64Encode(response.bodyBytes);
      _playBase64(base64Audio);
    } else {
      debugPrint('TTS backend error: ${response.statusCode}');
      _completionHandler?.call();
    }
  } catch (e) {
    debugPrint('TTS error: $e');
    _completionHandler?.call();
  }
}

void _playBase64(String base64Audio) {
  final dataUrl = 'data:audio/mpeg;base64,$base64Audio';
  final audio = _Audio(dataUrl.toJS);

  audio.onended = ((JSAny event) {
    _currentAudio = null;
    _completionHandler?.call();
  }).toJS;

  audio.onerror = ((JSAny event) {
    debugPrint('TTS audio playback error');
    _currentAudio = null;
    _completionHandler?.call();
  }).toJS;

  _currentAudio = audio;
  audio.play();
}

Future<void> stopSpeaking() async {
  final audio = _currentAudio;
  if (audio != null) {
    audio.pause();
    audio.currentTime = 0.toJS;
    audio.onended = null;
    audio.onerror = null;
    _currentAudio = null;
    _cancelHandler?.call();
  }
}
