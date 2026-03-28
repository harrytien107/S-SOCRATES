import 'dart:async';
import 'package:flutter/material.dart';
import 'package:voice_chat_app/services/api_service.dart';
import 'package:voice_chat_app/services/api_config.dart';
import 'package:voice_chat_app/services/tts_service.dart';
import 'package:voice_chat_app/stage/robot_ui_state.dart';

class RobotController {
  final ValueNotifier<RobotUiState> state = ValueNotifier(RobotUiState.idle);
  final ValueNotifier<String> currentMessage = ValueNotifier('');
  
  Timer? _pollingTimer;
  String? _lastCommandText;
  bool _isProcessing = false;

  void startPolling() {
    _pollingTimer?.cancel();
    _pollingTimer = Timer.periodic(const Duration(seconds: 1), (_) => _poll());
    debugPrint('Robot Polling Started');
  }

  void stopPolling() {
    _pollingTimer?.cancel();
    TtsService.stop();
    debugPrint('Robot Polling Stopped');
  }

  Future<void> _poll() async {
    if (_isProcessing) return;

    debugPrint('Polling backend at: ${ApiConfig.baseUrl}');
    final command = await ApiService.getLatestCommand();
    if (command != null) {
      debugPrint('Received new command');
      final text = command['text'] as String;
      final emotion = command['emotion'] as String;

      if (text != _lastCommandText && text.isNotEmpty) {
        _lastCommandText = text;
        _processCommand(text, emotion);
      }
    }
  }

  Future<void> _processCommand(String text, String emotion) async {
    _isProcessing = true;
    _lastCommandText = text;
    debugPrint('Process Command: $text ($emotion)');

    try {
      // 1. Thinking state
      state.value = RobotUiState.thinking;
      await Future.delayed(const Duration(milliseconds: 500));

      // 2. Set Emotion & Start Speaking
      currentMessage.value = text;
      state.value = (emotion == 'challenge') 
        ? RobotUiState.challenge 
        : RobotUiState.speaking;

      debugPrint('State -> ${state.value}');
      
      // 3. Trigger TTS
      TtsService.setOnComplete(() {
        debugPrint('TTS Callback: Finished');
        state.value = RobotUiState.idle;
        currentMessage.value = '';
        _isProcessing = false;
      });

      await TtsService.speak(text);
    } catch (e) {
      debugPrint('Process Error: $e');
      state.value = RobotUiState.error;
      _isProcessing = false;
    }
  }

  void dispose() {
    stopPolling();
    state.dispose();
    currentMessage.dispose();
  }
}
