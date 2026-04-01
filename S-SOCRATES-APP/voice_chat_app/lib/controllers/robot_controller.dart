import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/material.dart';
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';
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
  Timer? _micPollTimer;
  String? _lastCommandSignature;
  bool _isProcessing = false;
  bool _isMicBusy = false;
  int _pollFailureCount = 0;
  String _lastMicStatus = 'idle';

  final AudioRecorder _audioRecorder = AudioRecorder();
  final AgentAPI _agentAPI = AgentAPI();

  void startPolling() {
    _pollingTimer?.cancel();
    _micPollTimer?.cancel();
    // Timer 1: Poll robot-command (TTS, emotion...) — 500ms
    _pollingTimer = Timer.periodic(const Duration(milliseconds: 500), (_) => _pollCommands());
    // Timer 2: Poll Mic từ Đạo diễn — 300ms, chạy SONG SONG, ĐỘC LẬP
    _micPollTimer = Timer.periodic(const Duration(milliseconds: 300), (_) => _pollMicStatus());
    debugPrint('Robot Polling Started (command 500ms + mic 300ms)');
  }

  void stopPolling() {
    _pollingTimer?.cancel();
    _micPollTimer?.cancel();
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

  // ============================================
  // Audio Recording
  // ============================================
  Future<void> startRecordingAudio() async {
    _remoteLog('startRecordingAudio() CALLED');
    try {
      // Dọn sạch session cũ nếu recorder đang bận
      if (await _audioRecorder.isRecording()) {
        _remoteLog('recorder WAS busy — stopping first');
        await _audioRecorder.stop();
        await Future.delayed(const Duration(milliseconds: 200));
      }

      final hasPerm = await _audioRecorder.hasPermission();
      _remoteLog('hasPermission = $hasPerm');

      if (hasPerm) {
        final dir = await getApplicationDocumentsDirectory();
        final path = '${dir.path}/robot_audio_${DateTime.now().millisecondsSinceEpoch}.m4a';
        
        await _audioRecorder.start(
          const RecordConfig(encoder: AudioEncoder.aacLc, bitRate: 128000),
          path: path,
        );

        final isRec = await _audioRecorder.isRecording();
        _remoteLog('Recording started! isRecording=$isRec path=$path');
      } else {
        _remoteLog('PERMISSION DENIED — nhưng KHÔNG đổi state');
        // KHÔNG set state = error — để screen tự xử lý
      }
    } catch (e) {
      _remoteLog('ERROR in startRecordingAudio: $e');
      // KHÔNG set state = error — tránh cascade
    }
  }

  // Remote debug log — gửi HTTP lên backend để ta thấy trên server console
  void _remoteLog(String msg) {
    debugPrint('📱 $msg');
    try {
      http.post(
        Uri.parse('${ApiConfig.baseUrl}/robot/log'),
        headers: {'Content-Type': 'application/json'},
        body: '{"message": "${msg.replaceAll('"', '\\"')}"}',
      );
    } catch (_) {}
  }

  Future<void> cancelRecording() async {
    try {
      await _audioRecorder.stop();
      state.value = RobotUiState.idle;
      debugPrint('Canceled recording and reset state.');
    } catch (e) {
      debugPrint('Cancel recording error: $e');
    }
  }

  Future<void> stopRecordingAndProcess() async {
    try {
      // Giữ orb ở trạng thái "đang gửi" xuyên suốt toàn bộ lúc stop mic,
      // upload file và chờ backend/Deepgram xử lý xong.
      state.value = RobotUiState.uploading;
      
      final path = await _audioRecorder.stop();
      if (path == null) {
        _remoteLog('stopRecordingAndProcess failed: path is null (did mic actually start?)');
        
        // Hiện giả lập "Đang gửi" 1.5s để user bên Web biết điện thoại có nhận lệnh
        await Future.delayed(const Duration(milliseconds: 1500));
        
        currentMessage.value = 'Chưa ghi được âm thanh. Hãy thử lại.';
        state.value = RobotUiState.idle;
        return;
      }

      debugPrint('Stopped recording, path: $path');

      final result = await _agentAPI.processAudio(path);
      if (result == null) {
        _remoteLog('processAudio returned null');
        currentMessage.value = 'Không gửi được audio lên server.';
        state.value = RobotUiState.error;
        return;
      }

      latestTranscriptResult.value = result;

      final transcript = (result?['transcript'] as String?)?.trim() ?? '';
      final normalized = transcript.toLowerCase();
      if (transcript.isEmpty) {
        currentMessage.value = '';
        state.value = RobotUiState.idle;
        return;
      }

      if (transcript.isNotEmpty &&
          (normalized.contains('khong nhan duoc voice') ||
              normalized.contains('không nhận được voice'))) {
        currentMessage.value = transcript;
        state.value = RobotUiState.idle;
        return;
      }

      // Khi đã có transcript hợp lệ, robot chuyển sang "thinking"
      // để chờ operator xử lý và gửi câu trả lời tiếp theo.
      currentMessage.value = transcript;
      state.value = RobotUiState.thinking;
    } catch (e) {
      debugPrint('Stop recording error: $e');
      state.value = RobotUiState.error;
    }
  }

  // ============================================
  // Manual Tap — Đồng bộ ngược lên Backend
  // ============================================
  Future<void> manualStartRecording() async {
    // 1. Báo Backend: "Tôi tự bật mic"
    await _agentAPI.sendMicControl('start');
    // 2. Cập nhật local để poll không trigger lần nữa
    _lastMicStatus = 'listening';
    // 3. Bật mic thật
    state.value = RobotUiState.listening;
    await startRecordingAudio();
  }

  Future<void> manualStopRecording() async {
    // 1. Báo Backend: "Tôi tự tắt mic và gửi audio"
    await _agentAPI.sendMicControl('stop');
    // 2. Cập nhật local để poll không trigger lần nữa
    _lastMicStatus = 'processing';
    // 3. Tắt mic + upload
    await stopRecordingAndProcess();
    // 4. Báo hoàn tất
    await _agentAPI.notifyMicDone();
  }

  // ============================================
  // MIC POLL — Chạy hoàn toàn ĐỘC LẬP
  // Không bị _isProcessing hay TTS chặn.
  // ============================================
  Future<void> _pollMicStatus() async {
    if (_isMicBusy) return;
    
    try {
      final status = await _agentAPI.getMicStatus();
      if (status == _lastMicStatus) return;

      final prev = _lastMicStatus;
      _lastMicStatus = status;
      debugPrint('🎛️ Mic status: $prev → $status');

      _isMicBusy = true;

      if (status == 'listening' && prev != 'listening') {
        state.value = RobotUiState.listening;
        await startRecordingAudio();
      } else if (status == 'processing' && prev == 'listening') {
        await stopRecordingAndProcess();
        await _agentAPI.notifyMicDone();
      } else if (status == 'canceled' && prev == 'listening') {
        await cancelRecording();
        await _agentAPI.notifyMicDone();
      }

      _isMicBusy = false;
    } catch (err) {
      _isMicBusy = false;
    }
  }

  // ============================================
  // COMMAND POLL — Poll robot-command (TTS, emotion)
  // ============================================
  Future<void> _pollCommands() async {
    if (_isProcessing) return;

    Map<String, dynamic>? command;
    bool reachable = false;

    try {
      final response = await http
          .get(Uri.parse('${ApiConfig.baseUrl}/robot-command'))
          .timeout(const Duration(seconds: 4));

      if (response.statusCode == 200) {
        reachable = true;
        final data = jsonDecode(response.body);
        if (data != null && data is Map<String, dynamic>) {
          command = data;
        }
      }
    } catch (e) {
      debugPrint('Polling Error: $e');
    }

    if (reachable) {
      _pollFailureCount = 0;
      if (!isBackendReachable.value) {
        isBackendReachable.value = true;
        if (state.value == RobotUiState.error) {
          state.value = RobotUiState.idle;
        }
      }
    } else {
      _pollFailureCount += 1;
      if (_pollFailureCount >= 5 && isBackendReachable.value) {
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
        case 'uploading':
          mappedState = RobotUiState.uploading;
          break;
        case 'speaking':
          mappedState = RobotUiState.speaking;
          break;
        case 'challenge':
          mappedState = RobotUiState.challenge;
          break;
        case 'no_voice':
          mappedState = RobotUiState.idle;
          break;
        case 'error':
          mappedState = RobotUiState.error;
          break;
        default:
          mappedState = RobotUiState.idle;
      }

      // === NO VOICE ===
      if (emotion == 'no_voice') {
        currentMessage.value = text.isEmpty
            ? 'Không nhận được voice. Vui lòng nói lại.'
            : text;
        state.value = RobotUiState.idle;
        _isProcessing = false;
        return;
      }

      // === LISTENING — Chỉ set state, screen sẽ tự bật mic ===
      if (mappedState == RobotUiState.listening) {
        debugPrint('🎙️ Command: LISTENING → set state (screen sẽ bật mic)');
        state.value = RobotUiState.listening;
        _isProcessing = false;  // Cho phép poll tiếp để nhận lệnh uploading
        return;
      }

      // === UPLOADING — Chỉ set state, screen sẽ tự tắt mic + gửi ===
      if (mappedState == RobotUiState.uploading) {
        debugPrint('📤 Command: UPLOADING → set state (screen sẽ tắt mic + gửi)');
        state.value = RobotUiState.uploading;
        _isProcessing = false;  // PHẢI false để poll tiếp hoạt động
        return;
      }

      // === SPEAKING / CHALLENGE — Phát TTS ===
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

      // === Các emotion khác (neutral, error...) ===
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
