import 'dart:async';
import 'package:flutter/material.dart';
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';
import 'package:voice_chat_app/services/api_service.dart';
import 'package:voice_chat_app/services/api_config.dart';
import 'package:voice_chat_app/services/agent_api.dart';
import 'package:voice_chat_app/services/tts_service.dart';
import 'package:voice_chat_app/stage/robot_ui_state.dart';

class RobotController {
  final ValueNotifier<RobotUiState> state = ValueNotifier(RobotUiState.idle);
  final ValueNotifier<String> currentMessage = ValueNotifier('');
  final ValueNotifier<Map<String, dynamic>?> latestTranscriptResult = ValueNotifier(null);
  
  Timer? _pollingTimer;
  String? _lastCommandText;
  bool _isProcessing = false;

  final AudioRecorder _audioRecorder = AudioRecorder();
  final AgentAPI _agentAPI = AgentAPI();

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

  Future<void> startRecordingAudio() async {
    try {
      if (await _audioRecorder.hasPermission()) {
        final dir = await getApplicationDocumentsDirectory();
        final path = '${dir.path}/robot_audio_${DateTime.now().millisecondsSinceEpoch}.m4a';
        
        await _audioRecorder.start(
          const RecordConfig(encoder: AudioEncoder.aacLc, bitRate: 128000),
          path: path,
        );
        debugPrint('Started recording: $path');
      } else {
        debugPrint('Audio permission denied.');
        state.value = RobotUiState.error;
      }
    } catch (e) {
      debugPrint('Start recording error: $e');
      state.value = RobotUiState.error;
    }
  }

  Future<void> stopRecordingAndProcess() async {
    try {
      final path = await _audioRecorder.stop();
      if (path == null) {
        state.value = RobotUiState.idle;
        return;
      }

      debugPrint('Stopped recording, path: $path');

      state.value = RobotUiState.uploading;

      final result = await _agentAPI.processAudio(path);
      latestTranscriptResult.value = result;

      state.value = RobotUiState.thinking; // giữ nguyên ở đây
    } catch (e) {
      debugPrint('Stop recording error: $e');
      state.value = RobotUiState.error;
    }
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
    _audioRecorder.dispose();
    state.dispose();
    currentMessage.dispose();
    latestTranscriptResult.dispose();
  }
}
