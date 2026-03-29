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
  final ValueNotifier<bool> isBackendReachable = ValueNotifier(true);
  final ValueNotifier<Map<String, dynamic>?> latestTranscriptResult = ValueNotifier(null);
  
  Timer? _pollingTimer;
  String? _lastCommandSignature;
  bool _isProcessing = false;
  int _pollFailureCount = 0;

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

  void clearConnectionWarning() {
    if (!isBackendReachable.value) {
      isBackendReachable.value = true;
    }
    if (state.value == RobotUiState.error) {
      state.value = RobotUiState.idle;
    }
    _pollFailureCount = 0;
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

      final transcript = (result?['transcript'] as String?)?.trim() ?? '';
      final normalized = transcript.toLowerCase();
      if (transcript.isNotEmpty &&
          (normalized.contains('khong nhan duoc voice') ||
              normalized.contains('không nhận được voice'))) {
        currentMessage.value = transcript;
        state.value = RobotUiState.noVoice;
        return;
      }

      state.value = RobotUiState.thinking; // giữ nguyên ở đây
    } catch (e) {
      debugPrint('Stop recording error: $e');
      state.value = RobotUiState.error;
    }
  }

  Future<void> _poll() async {
    if (_isProcessing) return;

    debugPrint('Polling backend at: ${ApiConfig.baseUrl}');
    final pollResult = await ApiService.getLatestCommand();
    final command = pollResult.command;

    if (pollResult.reachable) {
      _pollFailureCount = 0;
      if (!isBackendReachable.value) {
        isBackendReachable.value = true;
        if (state.value == RobotUiState.error) {
          state.value = RobotUiState.idle;
        }
      }
    } else {
      _pollFailureCount += 1;
      // Avoid flaky false alarms when one poll misses.
      if (_pollFailureCount >= 10 && isBackendReachable.value) {
        isBackendReachable.value = false;
        state.value = RobotUiState.error;
      }
    }

    if (command != null) {
      debugPrint('Received new command');
      final text = ((command['text'] ?? '') as String).trim();
      final emotion = ((command['emotion'] ?? 'neutral') as String).trim().toLowerCase();
      final signature = '${command['timestamp'] ?? ''}|$emotion|$text';

      if (signature != _lastCommandSignature) {
        _lastCommandSignature = signature;
        _processCommand(text, emotion);
      }
    }
  }

  Future<void> _processCommand(String text, String emotion) async {
    _isProcessing = true;
    debugPrint('Process Command: $text ($emotion)');

    try {
      RobotUiState mappedState = RobotUiState.idle;
      switch (emotion) {
        case 'listening':
          mappedState = RobotUiState.listening;
          break;
        case 'speaking':
          mappedState = RobotUiState.speaking;
          break;
        case 'challenge':
          mappedState = RobotUiState.challenge;
          break;
        case 'no_voice':
          mappedState = RobotUiState.noVoice;
          break;
        case 'error':
          mappedState = RobotUiState.idle;
          break;
        default:
          mappedState = RobotUiState.idle;
      }

      if (emotion == 'no_voice') {
        currentMessage.value = text.isEmpty
            ? 'Không nhận được voice. Vui lòng nói lại.'
            : text;
        state.value = RobotUiState.noVoice;
        _isProcessing = false;
        return;
      }

      // speaking/challenge require text and trigger TTS.
      if (mappedState == RobotUiState.speaking || mappedState == RobotUiState.challenge) {
        if (text.isEmpty) {
          debugPrint('Skip speaking/challenge command because text is empty.');
          state.value = RobotUiState.error;
          currentMessage.value = '';
          _isProcessing = false;
          return;
        }

        state.value = RobotUiState.thinking;
        currentMessage.value = text;
        state.value = mappedState;
        debugPrint('State -> ${state.value}');

        TtsService.setOnComplete(() {
          debugPrint('TTS Callback: Finished');
          state.value = RobotUiState.idle;
          currentMessage.value = '';
          _isProcessing = false;
        });

        await TtsService.speak(text);
        return;
      }

      currentMessage.value = text;
      state.value = mappedState;
      debugPrint('State -> ${state.value}');
      _isProcessing = false;
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
    isBackendReachable.dispose();
    latestTranscriptResult.dispose();
  }
}
