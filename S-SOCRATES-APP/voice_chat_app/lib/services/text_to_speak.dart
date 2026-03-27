import 'dart:convert';
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:audioplayers/audioplayers.dart';
import 'package:voice_chat_app/services/api_config.dart';

// Conditional import: chỉ import dart:js_interop khi chạy trên web
import 'package:voice_chat_app/services/web_audio_stub.dart'
    if (dart.library.js_interop) 'dart:js_interop';

@JS('Audio')
extension type _Audio._(JSObject _) implements JSObject {
  external _Audio([JSString? src]);
  external JSPromise<JSAny?> play();
  external void pause();
  external set currentTime(JSNumber value);
  external set onended(JSFunction? handler);
  external set onerror(JSFunction? handler);
}



// Biến lưu trữ audio element trên Web
dynamic _currentWebAudio;
// Biến lưu trữ player trên Desktop/Mobile
final AudioPlayer _audioPlayer = AudioPlayer();

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
    final uri = Uri.parse('${ApiConfig.baseUrl}/tts');
    final response = await http
        .post(
          uri,
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'text': text}),
        )
        .timeout(const Duration(seconds: 60));

    if (response.statusCode == 200) {
      final base64Audio = base64Encode(response.bodyBytes);
      if (kIsWeb) {
        _playWeb(base64Audio);
      } else {
        await _playNative(base64Audio);
      }
    } else {
      debugPrint('TTS backend error: ${response.statusCode}');
      _completionHandler?.call();
    }
  } catch (e) {
    debugPrint('TTS error: $e');
    _completionHandler?.call();
  }
}

void _playWeb(String base64Audio) {
  final dataUrl = 'data:audio/mpeg;base64,$base64Audio';
  final audio = _Audio(dataUrl.toJS);

  audio.onended = ((JSAny event) {
    _currentWebAudio = null;
    _completionHandler?.call();
  }).toJS;

  audio.onerror = ((JSAny event) {
    debugPrint('TTS audio playback error (Web)');
    _currentWebAudio = null;
    _completionHandler?.call();
  }).toJS;

  _currentWebAudio = audio;
  audio.play();
}

Future<void> _playNative(String base64Audio) async {
  try {
    final bytes = base64Decode(base64Audio);
    
    // Đăng ký sự kiện khi phát xong
    _audioPlayer.onPlayerComplete.listen((_) {
      _completionHandler?.call();
    });

    await _audioPlayer.play(BytesSource(bytes));
  } catch (e) {
    debugPrint('TTS audio playback error (Native): $e');
    _completionHandler?.call();
  }
}

Future<void> stopSpeaking() async {
  if (kIsWeb) {
    final audio = _currentWebAudio;
    if (audio != null) {
      audio.pause();
      audio.currentTime = 0.toJS;
      audio.onended = null;
      audio.onerror = null;
      _currentWebAudio = null;
      _cancelHandler?.call();
    }
  } else {
    await _audioPlayer.stop();
    _cancelHandler?.call();
  }
}
