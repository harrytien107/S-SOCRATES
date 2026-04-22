import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/material.dart';
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:voice_chat_app/services/api_config.dart';
import 'package:voice_chat_app/services/agent_api.dart';
import 'package:voice_chat_app/services/robot_control_server.dart';
import 'package:voice_chat_app/services/tts_service.dart';
import 'package:voice_chat_app/stage/robot_ui_state.dart';

class RobotController {
  final ValueNotifier<RobotUiState> state = ValueNotifier(RobotUiState.idle);
  final ValueNotifier<String> currentMessage = ValueNotifier('');
  final ValueNotifier<bool> isBackendReachable = ValueNotifier(true);
  final ValueNotifier<Map<String, dynamic>?> latestTranscriptResult =
      ValueNotifier(null);

  String _lastMicStatus = 'idle';
  Timer? _backendHealthTimer;
  bool _isCheckingBackend = false;
  WebSocketChannel? _robotWsChannel;
  StreamSubscription<dynamic>? _robotWsSubscription;
  Timer? _robotWsReconnectTimer;
  bool _robotWsConnected = false;
  int _robotWsReconnectAttempts = 0;
  bool _robotWsStopped = false;

  final AudioRecorder _audioRecorder = AudioRecorder();
  final AgentAPI _agentAPI = AgentAPI();
  late final RobotControlServer _robotControlServer = RobotControlServer(
    onMicAction: _handleRemoteMicAction,
    onCommand: _handleRemoteCommand,
    getSnapshot: _buildControlSnapshot,
  );

  void startPolling() {
    _robotWsStopped = false;
    _connectRobotWebSocket();
    unawaited(_robotControlServer.start());
    debugPrint('Robot direct control server started on port 9000');
    unawaited(refreshBackendStatus());
    _backendHealthTimer?.cancel();
    _backendHealthTimer = Timer.periodic(
      const Duration(seconds: 3),
      (_) => unawaited(refreshBackendStatus()),
    );
  }

  void stopPolling() {
    _robotWsStopped = true;
    _disconnectRobotWebSocket();
    _backendHealthTimer?.cancel();
    _backendHealthTimer = null;
    unawaited(_robotControlServer.stop());
    TtsService.stop();
    debugPrint('Robot direct control stopped');
  }

  Future<void> refreshBackendStatus() async {
    if (_isCheckingBackend) return;
    _isCheckingBackend = true;
    try {
      var reachable = _robotWsConnected;
      if (!reachable) {
        reachable = await _agentAPI.pingBackend();
      }
      if (isBackendReachable.value != reachable) {
        isBackendReachable.value = reachable;
      }
      if (!reachable) {
        currentMessage.value = 'Mất kết nối tới backend.';
        state.value = RobotUiState.error;
      } else if (state.value == RobotUiState.error &&
          currentMessage.value == 'Mất kết nối tới backend.') {
        currentMessage.value = '';
        state.value = RobotUiState.idle;
      }
    } finally {
      _isCheckingBackend = false;
    }
  }

  void _connectRobotWebSocket() {
    if (_robotWsStopped) return;
    _robotWsReconnectTimer?.cancel();
    _robotWsReconnectTimer = null;

    final wsUrl = ApiConfig.robotWebSocketUrl;
    try {
      final channel = WebSocketChannel.connect(Uri.parse(wsUrl));
      _robotWsChannel = channel;
      _robotWsSubscription?.cancel();
      _robotWsSubscription = channel.stream.listen(
        _handleRobotWebSocketMessage,
        onError: (Object error, StackTrace stackTrace) {
          debugPrint('Robot WebSocket error: $error');
          _onRobotWebSocketDisconnected();
        },
        onDone: _onRobotWebSocketDisconnected,
        cancelOnError: true,
      );
      _robotWsConnected = true;
      _robotWsReconnectAttempts = 0;
      isBackendReachable.value = true;
      debugPrint('Connecting robot websocket: $wsUrl');
    } catch (e) {
      debugPrint('Robot WebSocket connect failed: $e');
      _onRobotWebSocketDisconnected();
    }
  }

  void _onRobotWebSocketDisconnected() {
    if (_robotWsStopped) return;
    _robotWsConnected = false;

    _robotWsSubscription?.cancel();
    _robotWsSubscription = null;

    try {
      _robotWsChannel?.sink.close();
    } catch (_) {}
    _robotWsChannel = null;

    _scheduleRobotWebSocketReconnect();
  }

  void _scheduleRobotWebSocketReconnect() {
    if (_robotWsStopped || _robotWsReconnectTimer != null) return;

    _robotWsReconnectAttempts += 1;
    var delaySeconds = 1;
    if (_robotWsReconnectAttempts > 4) {
      delaySeconds = 5;
    } else if (_robotWsReconnectAttempts > 1) {
      delaySeconds = 2;
    }

    _robotWsReconnectTimer = Timer(Duration(seconds: delaySeconds), () {
      _robotWsReconnectTimer = null;
      _connectRobotWebSocket();
    });
  }

  void _disconnectRobotWebSocket() {
    _robotWsReconnectTimer?.cancel();
    _robotWsReconnectTimer = null;
    _robotWsReconnectAttempts = 0;
    _robotWsConnected = false;

    _robotWsSubscription?.cancel();
    _robotWsSubscription = null;

    try {
      _robotWsChannel?.sink.close();
    } catch (_) {}
    _robotWsChannel = null;
  }

  void _handleRobotWebSocketMessage(dynamic raw) {
    if (!_robotWsConnected) {
      _robotWsConnected = true;
      _robotWsReconnectAttempts = 0;
      isBackendReachable.value = true;
      if (state.value == RobotUiState.error &&
          currentMessage.value == 'Mất kết nối tới backend.') {
        state.value = RobotUiState.idle;
        currentMessage.value = '';
      }
      debugPrint('Robot websocket connected and ready.');
    }

    try {
      final decoded = raw is String ? jsonDecode(raw) : raw;
      if (decoded is! Map) return;

      final data = Map<String, dynamic>.from(decoded);
      final type = (data['type'] ?? '').toString().trim().toLowerCase();

      if (type == 'mic_status') {
        final status = (data['status'] ?? '').toString().trim().toLowerCase();
        if (status == 'listening') {
          unawaited(_handleRemoteMicAction('start'));
        } else if (status == 'processing') {
          unawaited(_handleRemoteMicAction('stop'));
        } else if (status == 'canceled') {
          unawaited(_handleRemoteMicAction('cancel'));
        } else if (status == 'idle') {
          _lastMicStatus = 'idle';
        }
      } else if (type == 'command') {
        final text = (data['text'] ?? '').toString();
        final emotion = (data['emotion'] ?? 'neutral').toString();
        unawaited(_handleRemoteCommand(text, emotion));
      } else if (type == 'stop_tts') {
        unawaited(_handleRemoteCommand('', 'stop_tts'));
      } else if (type == 'ping') {
        _sendRobotSocketMessage({'type': 'pong'});
      }
    } catch (e) {
      debugPrint('Robot websocket parse error: $e');
    }
  }

  bool _sendRobotSocketMessage(Map<String, dynamic> payload) {
    final channel = _robotWsChannel;
    if (!_robotWsConnected || channel == null) {
      return false;
    }

    try {
      channel.sink.add(jsonEncode(payload));
      return true;
    } catch (e) {
      debugPrint('Robot websocket send error: $e');
      _robotWsConnected = false;
      return false;
    }
  }

  Future<void> _notifyManualMicAction(String action) async {
    final sent = _sendRobotSocketMessage({'type': 'manual_mic', 'action': action});
    if (!sent) {
      await _agentAPI.sendMicControl(action);
    }
  }

  Future<void> _notifyMicDone() async {
    final sent = _sendRobotSocketMessage({'type': 'mic_done'});
    if (!sent) {
      await _agentAPI.notifyMicDone();
    }
  }

  void clearConnectionWarning() {
    if (!isBackendReachable.value) {
      isBackendReachable.value = true;
    }
    if (state.value == RobotUiState.error) {
      state.value = RobotUiState.idle;
    }
  }

  void reconnectBackend() {
    _robotWsStopped = false;
    _disconnectRobotWebSocket();
    _connectRobotWebSocket();
    unawaited(refreshBackendStatus());
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
        final path =
            '${dir.path}/robot_audio_${DateTime.now().millisecondsSinceEpoch}.m4a';

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
    if (_sendRobotSocketMessage({'type': 'log', 'message': msg})) {
      return;
    }
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
      // Flow cố định do operator điều khiển:
      // idle -> listening -> uploading -> thinking -> speaking -> idle
      // Không tự rơi về idle chỉ vì transcript rỗng/no-voice nữa.
      state.value = RobotUiState.uploading;

      final path = await _audioRecorder.stop();
      if (path == null) {
        _remoteLog(
          'stopRecordingAndProcess failed: path is null (did mic actually start?)',
        );
        currentMessage.value = '';
        state.value = RobotUiState.thinking;
        return;
      }

      debugPrint('Stopped recording, path: $path');

      final result = await _agentAPI.processAudio(path);
      if (result == null) {
        isBackendReachable.value = false;
        _remoteLog('processAudio returned null');
        currentMessage.value = 'Không gửi được audio lên server.';
        state.value = RobotUiState.error;
        return;
      }

      isBackendReachable.value = true;
      latestTranscriptResult.value = result;

      final transcript = (result['transcript'] as String?)?.trim() ?? '';
      // Kể cả transcript rỗng hoặc fallback no-voice, robot vẫn đứng ở
      // trạng thái thinking để operator quyết định bước tiếp theo trên web.
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
    _lastMicStatus = 'listening';
    await _notifyManualMicAction('start');
    state.value = RobotUiState.listening;
    await startRecordingAudio();
  }

  Future<void> manualStopRecording() async {
    _lastMicStatus = 'processing';
    await _notifyManualMicAction('stop');
    await stopRecordingAndProcess();
    _lastMicStatus = 'idle';
    await _notifyMicDone();
  }

  Map<String, dynamic> _buildControlSnapshot() {
    return {
      'state': state.value.name,
      'message': currentMessage.value,
      'backendReachable': isBackendReachable.value,
      'micStatus': _lastMicStatus,
    };
  }

  Future<void> _handleRemoteMicAction(String action) async {
    final prev = _lastMicStatus;
    _lastMicStatus = action == 'start'
        ? 'listening'
        : action == 'stop'
        ? 'processing'
        : 'canceled';
    debugPrint('🎛️ Direct mic control: $prev -> $_lastMicStatus');

    if (action == 'start' && prev != 'listening') {
      state.value = RobotUiState.listening;
      unawaited(startRecordingAudio());
      return;
    }

    if (action == 'stop' && prev == 'listening') {
      unawaited(() async {
        await stopRecordingAndProcess();
        _lastMicStatus = 'idle';
        await _notifyMicDone();
      }());
      return;
    }

    if (action == 'cancel' && prev == 'listening') {
      unawaited(() async {
        await cancelRecording();
        _lastMicStatus = 'idle';
        await _notifyMicDone();
      }());
    }
  }

  Future<void> _handleRemoteCommand(String text, String emotion) async {
    isBackendReachable.value = true;
    await _processCommand(text, emotion);
  }

  Future<void> _processCommand(String text, String emotion) async {
    debugPrint('Process Command: $text ($emotion)');

    try {
      final normalizedEmotion = emotion.trim().toLowerCase().replaceAll('-', '_');

      if (normalizedEmotion == 'stop_tts' || normalizedEmotion == 'stoptts') {
        await TtsService.stop();
        currentMessage.value = '';
        state.value = RobotUiState.idle;
        debugPrint('State -> RobotUiState.idle (stop_tts)');
        return;
      }

      RobotUiState mappedState = RobotUiState.idle;
      switch (normalizedEmotion) {
        case 'idle':
        case 'neutral':
          mappedState = RobotUiState.idle;
          break;
        case 'listening':
          mappedState = RobotUiState.listening;
          break;
        case 'uploading':
          mappedState = RobotUiState.uploading;
          break;
        case 'speaking':
          mappedState = RobotUiState.speaking;
          break;
        case 'no_voice':
          mappedState = RobotUiState.thinking;
          break;
        case 'error':
          mappedState = RobotUiState.error;
          break;
        default:
          mappedState = RobotUiState.idle;
      }

      // === NO VOICE ===
      if (normalizedEmotion == 'no_voice') {
        currentMessage.value = text;
        state.value = RobotUiState.thinking;
        return;
      }

      // === LISTENING — Chỉ set state, screen sẽ tự bật mic ===
      if (mappedState == RobotUiState.listening) {
        debugPrint('🎙️ Command: LISTENING → set state (screen sẽ bật mic)');
        if (_lastMicStatus != 'listening') {
          _lastMicStatus = 'listening';
          state.value = RobotUiState.listening;
          await startRecordingAudio();
        } else {
          state.value = RobotUiState.listening;
        }
        return;
      }

      // === UPLOADING — Chỉ set state, screen sẽ tự tắt mic + gửi ===
      if (mappedState == RobotUiState.uploading) {
        debugPrint(
          '📤 Command: UPLOADING → set state (screen sẽ tắt mic + gửi)',
        );
        if (_lastMicStatus == 'listening') {
          _lastMicStatus = 'processing';
          await stopRecordingAndProcess();
          _lastMicStatus = 'idle';
          await _agentAPI.notifyMicDone();
        } else {
          state.value = RobotUiState.uploading;
        }
        return;
      }

      // === SPEAKING — Phát TTS ===
      if (mappedState == RobotUiState.speaking) {
        if (text.isEmpty) {
          debugPrint('Skip speaking command because text is empty.');
          state.value = RobotUiState.error;
          currentMessage.value = '';
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
        });

        await TtsService.speak(text);
        return;
      }

      // === Các emotion khác (idle/neutral, error...) ===
      currentMessage.value = text;
      state.value = mappedState;
      debugPrint('State -> ${state.value}');
    } catch (e) {
      debugPrint('Process Error: $e');
      state.value = RobotUiState.error;
    }
  }

  void dispose() {
    stopPolling();
    _robotWsStopped = true;
    _disconnectRobotWebSocket();
    _audioRecorder.dispose();
    state.dispose();
    currentMessage.dispose();
    isBackendReachable.dispose();
    latestTranscriptResult.dispose();
  }
}
