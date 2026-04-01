import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/material.dart';
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:voice_chat_app/services/api_config.dart';
import 'package:voice_chat_app/services/agent_api.dart';
import 'package:voice_chat_app/services/tts_service.dart';
import 'package:voice_chat_app/stage/robot_ui_state.dart';

class RobotController {
  final ValueNotifier<RobotUiState> state = ValueNotifier(RobotUiState.error);
  final ValueNotifier<String> currentMessage = ValueNotifier('');
  final ValueNotifier<bool> isBackendReachable = ValueNotifier(false);
  final ValueNotifier<Map<String, dynamic>?> latestTranscriptResult = ValueNotifier(null);
  
  // ── WebSocket ──────────────────────────────────────────────────
  WebSocketChannel? _channel;
  Timer? _reconnectTimer;
  int _reconnectFailCount = 0;
  bool _wsConnected = false;
  String? _lastCommandSignature;
  bool _isProcessing = false;
  bool _isMicBusy = false;
  String _lastMicStatus = 'idle';

  // ── Fallback Polling (backup khi WS thất bại) ────────────────
  Timer? _pollingTimer;
  Timer? _micPollTimer;
  bool _usingFallbackPolling = false;
  int _pollFailureCount = 0;

  final AudioRecorder _audioRecorder = AudioRecorder();
  final AgentAPI _agentAPI = AgentAPI();

  // ── TTS Streaming Audio Queue ────────────────────────────────
  final Queue<Map<String, dynamic>> _audioQueue = Queue<Map<String, dynamic>>();
  bool _isPlayingQueue = false;

  // =============================================================
  //  KHỞI ĐỘNG — Kết nối WebSocket (Ưu tiên #1)
  // =============================================================
  void connectWebSocket() {
    _reconnectTimer?.cancel();
    _connectWs();
  }

  void _connectWs() {
    try {
      // Chuyển http://IP:8000 → ws://IP:8000/ws/robot
      final baseUrl = ApiConfig.baseUrl;
      final wsUrl = baseUrl
          .replaceFirst('https://', 'wss://')
          .replaceFirst('http://', 'ws://');
      final uri = Uri.parse('$wsUrl/ws/robot');

      debugPrint('🔌 Connecting WebSocket: $uri');
      _channel = WebSocketChannel.connect(uri);

      _channel!.stream.listen(
        _onMessage,
        onDone: _onDisconnected,
        onError: (error) {
          debugPrint('🔴 WebSocket Error: $error');
          _onDisconnected();
        },
      );

      // Lưu ý: Không bám vào giả định kết nối đã thành công ngay lập tức ở đây.
      // Chúng ta sẽ chờ gói tin đầu tiên (mic_status) từ server gởi về qua _onMessage()
      // để chính thức bật cờ _wsConnected = true và đổi UI state.

    } catch (e) {
      debugPrint('❌ WebSocket setup failed: $e');
      _onDisconnected();
    }
  }

  void _onDisconnected() {
    _wsConnected = false;
    _channel = null;
    _reconnectFailCount++;
    debugPrint('🔴 WebSocket disconnected (fail #$_reconnectFailCount)');

    // Sau 5 lần thất bại (~15s) → báo mất kết nối
    if (_reconnectFailCount >= 5 && isBackendReachable.value) {
      isBackendReachable.value = false;
      state.value = RobotUiState.error;
    }

    // Sau 10 lần thất bại (~30s) → chuyển sang fallback polling
    if (_reconnectFailCount >= 10 && !_usingFallbackPolling) {
      debugPrint('⚠️ WebSocket thất bại quá nhiều → chuyển sang Fallback Polling');
      _startFallbackPolling();
    }

    // Luôn thử reconnect mỗi 1.5 giây để phản hồi nhanh hơn khi Backend bật lại
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(const Duration(milliseconds: 1500), () {
      if (!_wsConnected) {
        _connectWs();
      }
    });
  }

  // =============================================================
  //  XỬ LÝ TIN NHẮN TỪ SERVER
  // =============================================================
  void _onMessage(dynamic raw) {
    _wsConnected = true; // Nhận được tin nhắn tức là đường truyền đang mở
    
    try {
      final data = raw is String ? jsonDecode(raw) : raw;
      if (data is! Map<String, dynamic>) return;

      final type = data['type'] as String? ?? '';

      if (type == 'mic_status') {
        _handleMicStatus(data['status'] as String? ?? 'idle');
      } else if (type == 'command') {
        _handleCommand(data);
      } else if (type == 'tts_chunk') {
        _handleTtsChunk(data);
      } else if (type == 'tts_done') {
        _handleTtsDone();
      }

      // Nếu nhận được tin nhắn → kết nối ổn
      if (!isBackendReachable.value) {
        debugPrint('🟢 WebSocket Connected & Validated!');
        isBackendReachable.value = true;
        _reconnectFailCount = 0;
        _usingFallbackPolling = false;
        _stopFallbackPolling();
        
        if (state.value == RobotUiState.error) {
          state.value = RobotUiState.idle;
        }
      }
      _reconnectFailCount = 0;
    } catch (e) {
      debugPrint('⚠️ _onMessage parse error: $e');
    }
  }

  void _handleMicStatus(String status) {
    if (status == _lastMicStatus) return;
    if (_isMicBusy) return;

    final prev = _lastMicStatus;
    _lastMicStatus = status;
    debugPrint('🎛️ WS Mic status: $prev → $status');

    _isMicBusy = true;

    _processMicChange(prev, status).whenComplete(() {
      _isMicBusy = false;
    });
  }

  Future<void> _processMicChange(String prev, String status) async {
    if (status == 'listening' && prev != 'listening') {
      state.value = RobotUiState.listening;
      await startRecordingAudio();
    } else if (status == 'processing' && prev == 'listening') {
      await stopRecordingAndProcess();
      _sendToServer({'type': 'mic_done'});
    } else if (status == 'canceled' && prev == 'listening') {
      await cancelRecording();
      _sendToServer({'type': 'mic_done'});
    }
  }

  void _handleCommand(Map<String, dynamic> data) {
    final text = ((data['text'] ?? '') as String).trim();
    final emotion = ((data['emotion'] ?? 'neutral') as String).trim().toLowerCase();
    final signature = '${data['timestamp'] ?? ''}|$emotion|$text';

    if (signature != _lastCommandSignature) {
      _lastCommandSignature = signature;
      _processCommand(text, emotion);
    }
  }

  // =============================================================
  //  TTS STREAMING — Audio Queue (phát từng câu nối đuôi nhau)
  // =============================================================
  void _handleTtsChunk(Map<String, dynamic> data) {
    final audioBase64 = data['audio'] as String? ?? '';
    final text = data['text'] as String? ?? '';
    final emotion = data['emotion'] as String? ?? 'speaking';
    final index = data['index'] as int? ?? 0;

    if (audioBase64.isEmpty) return;

    debugPrint('🔊 TTS Chunk arriving #$index: "${text.length > 30 ? text.substring(0, 30) : text}..."');

    // MỚI: Thêm CẢ audio, text và emotion vào queue, không update UI ngay
    _audioQueue.add({
      'audio': audioBase64,
      'text': text,
      'emotion': emotion,
    });

    // Bắt đầu phát nếu chưa phát
    if (!_isPlayingQueue) {
      _processAudioQueue();
    }
  }

  void _handleTtsDone() {
    debugPrint('🔊 TTS Streaming done!');
    // Nếu queue đã rỗng → chuyển về idle ngay
    // Nếu queue còn → chờ phát xong rồi mới idle
    if (_audioQueue.isEmpty && !_isPlayingQueue) {
      state.value = RobotUiState.idle;
      currentMessage.value = '';
    }
    // Nếu đang phát → _processAudioQueue sẽ tự chuyển idle khi xong
  }

  Future<void> _processAudioQueue() async {
    _isPlayingQueue = true;
    while (_audioQueue.isNotEmpty) {
      final chunkData = _audioQueue.removeFirst();
      final chunkBase64 = chunkData['audio'] as String;
      final text = chunkData['text'] as String;
      final emotion = chunkData['emotion'] as String;

      try {
        await TtsService.stop();
        
        // Cập nhật UI NHỮNG GÌ SẮP PHÁT (sync phụ đề với audio)
        currentMessage.value = text;
        state.value = (emotion == 'challenge') 
            ? RobotUiState.challenge 
            : RobotUiState.speaking;

        final bytes = base64Decode(chunkBase64);
        debugPrint('🔊 Playing chunk: ${bytes.length} bytes - "$text"');

        // Dùng AudioPlayer phát bytes trực tiếp
        final completer = Completer<void>();
        TtsService.setOnComplete(() {
          if (!completer.isCompleted) completer.complete();
        });

        // Phát audio
        await TtsService.speakFromBytes(bytes);
        // Chờ phát xong
        await completer.future.timeout(
          const Duration(seconds: 30),
          onTimeout: () => debugPrint('⚠️ Audio chunk timeout'),
        );
      } catch (e) {
        debugPrint('⚠️ Audio queue error: $e');
      }
    }
    _isPlayingQueue = false;
    // Nếu không còn chunk nào → chuyển về idle
    state.value = RobotUiState.idle;
    currentMessage.value = '';
  }

  // =============================================================
  //  GỬI TIN NHẮN LÊN SERVER QUA WEBSOCKET
  // =============================================================
  void _sendToServer(Map<String, dynamic> data) {
    if (_wsConnected && _channel != null) {
      try {
        _channel!.sink.add(jsonEncode(data));
      } catch (e) {
        debugPrint('⚠️ _sendToServer error: $e');
      }
    }
  }

  // ============================================
  // Audio Recording (GIỮ NGUYÊN 100%)
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

  // Remote debug log — gửi qua WebSocket (ưu tiên) hoặc HTTP (fallback)
  void _remoteLog(String msg) {
    debugPrint('📱 $msg');
    if (_wsConnected) {
      _sendToServer({'type': 'log', 'message': msg});
    } else {
      try {
        http.post(
          Uri.parse('${ApiConfig.baseUrl}/robot/log'),
          headers: {'Content-Type': 'application/json'},
          body: '{"message": "${msg.replaceAll('"', '\\"')}"}',
        );
      } catch (_) {}
    }
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
      // ✅ LUÔN CHUYỂN SANG ĐANG GỬI TRƯỚC ĐỂ UI 3D CẬP NHẬT NGAY LẬP TỨC
      state.value = RobotUiState.uploading;
      
      final path = await _audioRecorder.stop();
      if (path == null) {
        _remoteLog('stopRecordingAndProcess failed: path is null (did mic actually start?)');
        
        // Hiện giả lập "Đang gửi" 1.5s để user bên Web biết điện thoại có nhận lệnh
        await Future.delayed(const Duration(milliseconds: 1500));
        
        currentMessage.value = 'Chưa ghi được âm thanh. Hãy thử lại.';
        state.value = RobotUiState.noVoice; // show a clear visual indicator that it tried
        return;
      }

      debugPrint('Stopped recording, path: $path');

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
    // 1. Báo Backend qua WebSocket (hoặc HTTP fallback)
    if (_wsConnected) {
      _sendToServer({'type': 'manual_mic', 'action': 'start'});
    } else {
      await _agentAPI.sendMicControl('start');
    }
    // 2. Cập nhật local
    _lastMicStatus = 'listening';
    // 3. Bật mic thật
    state.value = RobotUiState.listening;
    await startRecordingAudio();
  }

  Future<void> manualStopRecording() async {
    // 1. Báo Backend qua WebSocket (hoặc HTTP fallback)
    if (_wsConnected) {
      _sendToServer({'type': 'manual_mic', 'action': 'stop'});
    } else {
      await _agentAPI.sendMicControl('stop');
    }
    // 2. Cập nhật local
    _lastMicStatus = 'processing';
    // 3. Tắt mic + upload
    await stopRecordingAndProcess();
    // 4. Báo hoàn tất qua WebSocket
    _sendToServer({'type': 'mic_done'});
  }

  // =============================================================
  //  FALLBACK POLLING (Chỉ bật khi WebSocket thất bại liên tục)
  // =============================================================
  void _startFallbackPolling() {
    if (_usingFallbackPolling) return;
    _usingFallbackPolling = true;
    debugPrint('🔄 Fallback Polling STARTED (command 500ms + mic 300ms)');

    _pollingTimer?.cancel();
    _micPollTimer?.cancel();
    _pollingTimer = Timer.periodic(const Duration(milliseconds: 500), (_) => _pollCommands());
    _micPollTimer = Timer.periodic(const Duration(milliseconds: 300), (_) => _pollMicStatus());
  }

  void _stopFallbackPolling() {
    if (!_usingFallbackPolling) return;
    _usingFallbackPolling = false;
    _pollingTimer?.cancel();
    _micPollTimer?.cancel();
    debugPrint('✅ Fallback Polling STOPPED (WebSocket restored)');
  }

  Future<void> _pollMicStatus() async {
    if (_isMicBusy) return;
    
    try {
      final status = await _agentAPI.getMicStatus();
      if (status == _lastMicStatus) return;

      final prev = _lastMicStatus;
      _lastMicStatus = status;
      debugPrint('🎛️ Poll Mic status: $prev → $status');

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
      _handleCommand(command);
    }
  }

  // =============================================================
  //  XỬ LÝ COMMAND (DÙNG CHUNG CHO CẢ WS VÀ POLLING)
  // =============================================================
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
          mappedState = RobotUiState.noVoice;
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
        state.value = RobotUiState.noVoice;
        _isProcessing = false;
        return;
      }

      // === LISTENING — Chỉ set state, screen sẽ tự bật mic ===
      if (mappedState == RobotUiState.listening) {
        debugPrint('🎙️ Command: LISTENING → set state (screen sẽ bật mic)');
        state.value = RobotUiState.listening;
        _isProcessing = false;  // Cho phép xử lý tiếp để nhận lệnh uploading
        return;
      }

      // === UPLOADING — Chỉ set state, screen sẽ tự tắt mic + gửi ===
      if (mappedState == RobotUiState.uploading) {
        debugPrint('📤 Command: UPLOADING → set state (screen sẽ tắt mic + gửi)');
        state.value = RobotUiState.uploading;
        _isProcessing = false;  // PHẢI false để nhận lệnh tiếp
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

  void clearConnectionWarning() {
    if (!isBackendReachable.value) {
      isBackendReachable.value = true;
    }
    if (state.value == RobotUiState.error) {
      state.value = RobotUiState.idle;
    }
    _pollFailureCount = 0;
    _reconnectFailCount = 0;
  }

  void dispose() {
    _reconnectTimer?.cancel();
    _pollingTimer?.cancel();
    _micPollTimer?.cancel();
    _channel?.sink.close();
    TtsService.stop();
    _audioRecorder.dispose();
    state.dispose();
    currentMessage.dispose();
    isBackendReachable.dispose();
    latestTranscriptResult.dispose();
    debugPrint('🛑 RobotController disposed');
  }
}
