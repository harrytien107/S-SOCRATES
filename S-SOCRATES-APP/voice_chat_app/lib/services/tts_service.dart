import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:voice_chat_app/services/api_config.dart';

// Conditional import for Web support
import 'package:voice_chat_app/services/web_audio_stub.dart'
    if (dart.library.js_interop) 'dart:js_interop';

@JS('Audio')
extension type _Audio._(JSObject _) implements JSObject {
  external _Audio([JSString? src]);
  external JSPromise<JSAny?> play();
  external void pause();
  external set currentTime(JSNumber value);
  external set onended(JSFunction? handler);
}

class TtsService {
  static final AudioPlayer _audioPlayer = AudioPlayer();
  static dynamic _currentWebAudio;
  static VoidCallback? _onComplete;

  static void setOnComplete(VoidCallback callback) {
    _onComplete = callback;
  }

  static Future<void> speak(String text) async {
    if (text.trim().isEmpty) return;
    await stop();

    try {
      final response = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/tts'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'text': text}),
      ).timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        final base64Audio = base64Encode(response.bodyBytes);
        if (kIsWeb) {
          _playWeb(base64Audio);
        } else {
          await _playNative(base64Audio);
        }
      } else {
        debugPrint('TTS Error: ${response.statusCode}');
        _onComplete?.call();
      }
    } catch (e) {
      debugPrint('TTS Error: $e');
      _onComplete?.call();
    }
  }

  static void _playWeb(String base64Audio) {
    final dataUrl = 'data:audio/mpeg;base64,$base64Audio';
    final audio = _Audio(dataUrl.toJS);

    audio.onended = ((JSAny event) {
      _currentWebAudio = null;
      _onComplete?.call();
    }).toJS;

    _currentWebAudio = audio;
    audio.play();
  }

  static Future<void> _playNative(String base64Audio) async {
    try {
      final bytes = base64Decode(base64Audio);
      debugPrint('TTS: Playing native audio (${bytes.length} bytes)');
      _audioPlayer.onPlayerComplete.first.then((_) {
        debugPrint('TTS: Native playback complete');
        _onComplete?.call();
      });
      await _audioPlayer.play(BytesSource(bytes));
    } catch (e) {
      debugPrint('Native Playback Error: $e');
      _onComplete?.call();
    }
  }

  static Future<void> stop() async {
    if (kIsWeb) {
      if (_currentWebAudio != null) {
        _currentWebAudio!.pause();
        _currentWebAudio = null;
      }
    } else {
      await _audioPlayer.stop();
    }
  }
}
