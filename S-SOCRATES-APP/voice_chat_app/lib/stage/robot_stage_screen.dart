import 'dart:async';
import 'package:flutter/material.dart';
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';

import 'robot_ui_state.dart';
import 'animated_background.dart';
import 'ai_orb_widget.dart';
import 'ai_status_badge.dart';
import 'ai_subtitle_panel.dart';
import '../services/agent_api.dart';
import '../services/text_to_speak.dart';
import '../services/api_config.dart';

/// Màn hình sân khấu chính — wireframe orb, tối giản
class RobotStageScreen extends StatefulWidget {
  const RobotStageScreen({super.key});

  @override
  State<RobotStageScreen> createState() => _RobotStageScreenState();
}

class _RobotStageScreenState extends State<RobotStageScreen> {
  // ── State machine ──────────────────────────────────────────────
  RobotUiState _uiState = RobotUiState.idle;
  String? _subtitle;
  String? _errorMessage;

  // ── Services ──────────────────────────────────────────────────
  final AgentAPI _api = AgentAPI();
  final AudioRecorder _recorder = AudioRecorder();

  // ── Recording / VAD ───────────────────────────────────────────
  StreamSubscription<Amplitude>? _amplitudeSub;
  Timer? _silenceTimer;
  int _sessionSeed = 0;
  int? _activeSessionId;
  bool _voiceSupported = true;
  static const double _silenceThreshold = -40.0;
  static const int _silenceDurationMs = 1800;

  // ── Mock / demo ────────────────────────────────────────────────
  bool _isMockMode = true;
  int _mockSubtitleIndex = 0;

  // ── Hint "tap" label ──────────────────────────────────────────
  bool _showHint = true;

  @override
  void initState() {
    super.initState();
    _initMic();
    _initTTSListeners();
    // Hide tap hint after 4 seconds
    Future.delayed(const Duration(seconds: 4), () {
      if (mounted) setState(() => _showHint = false);
    });
  }

  void _initTTSListeners() {
    setTTSCompletionHandler(() {
      if (!mounted) return;
      setState(() {
        _uiState = RobotUiState.idle;
        _subtitle = null;
      });
      Future.delayed(const Duration(milliseconds: 600), () {
        if (mounted && _uiState == RobotUiState.idle) _startListening();
      });
    });
    setTTSCancelHandler(() {
      if (!mounted) return;
      setState(() {
        _uiState = RobotUiState.idle;
        _subtitle = null;
      });
    });
  }

  Future<void> _initMic() async {
    final ok = await _recorder.hasPermission();
    if (mounted) setState(() => _voiceSupported = ok);
  }

  // ── Tap orb ───────────────────────────────────────────────────
  void _handleOrbTap() {
    setState(() => _showHint = false);
    if (_isMockMode) {
      _cycleMockState();
    } else {
      _handleRealTap();
    }
  }

  Future<void> _handleRealTap() async {
    switch (_uiState) {
      case RobotUiState.idle:
        await _startListening();
        break;
      case RobotUiState.listening:
        await _stopListening();
        break;
      case RobotUiState.speaking:
        await stopSpeaking();
        setState(() {
          _uiState = RobotUiState.idle;
          _subtitle = null;
        });
        break;
      default:
        break;
    }
  }

  void _cycleMockState() {
    final states = RobotUiState.values;
    final next = states[(states.indexOf(_uiState) + 1) % states.length];
    setState(() {
      _uiState = next;
      _subtitle = next == RobotUiState.speaking
          ? kMockSubtitles[_mockSubtitleIndex++ % kMockSubtitles.length]
          : null;
      _errorMessage =
          next == RobotUiState.error ? kMockErrorMessage : null;
    });
  }

  // ── Real voice flow ────────────────────────────────────────────
  bool _isActive(int id) => _activeSessionId == id;

  Future<void> _startListening() async {
    if (!_voiceSupported || _activeSessionId != null) return;
    try {
      if (await _recorder.isRecording()) await _recorder.stop();
    } catch (_) {}
    final sid = ++_sessionSeed;
    _activeSessionId = sid;
    setState(() {
      _uiState = RobotUiState.listening;
      _subtitle = null;
      _errorMessage = null;
    });
    try {
      final dir = await getTemporaryDirectory();
      final path = '${dir.path}/speech_$sid.m4a';
      await _recorder.start(
          const RecordConfig(encoder: AudioEncoder.aacLc), path: path);
      _amplitudeSub =
          _recorder.onAmplitudeChanged(const Duration(milliseconds: 100)).listen(
        (amp) {
          if (amp.current < _silenceThreshold) {
            _silenceTimer ??= Timer(
                const Duration(milliseconds: _silenceDurationMs),
                () {
              if (mounted && _isActive(sid)) _stopListening();
            });
          } else {
            _silenceTimer?.cancel();
            _silenceTimer = null;
          }
        },
      );
    } catch (e) {
      _activeSessionId = null;
      if (mounted) {
        setState(() {
          _uiState = RobotUiState.error;
          _errorMessage = 'Không thể bật mic: $e';
        });
      }
    }
  }

  Future<void> _stopListening() async {
    final sid = _activeSessionId;
    _activeSessionId = null;
    _amplitudeSub?.cancel();
    _amplitudeSub = null;
    _silenceTimer?.cancel();
    _silenceTimer = null;
    if (sid == null) return;
    setState(() => _uiState = RobotUiState.thinking);
    try {
      final path = await _recorder.stop();
      if (path == null || !mounted) return;
      final text = await _api.speechToText(path);
      if (text.trim().isEmpty) {
        setState(() {
          _uiState = RobotUiState.idle;
          _errorMessage = 'Không nghe rõ. Hãy thử lại.';
        });
        return;
      }
      await _sendToAI(text);
    } catch (e) {
      if (mounted) {
        setState(() {
          _uiState = RobotUiState.error;
          _errorMessage = 'Lỗi nhận diện giọng nói.';
        });
      }
    }
  }

  Future<void> _sendToAI(String text) async {
    try {
      final reply = await _api.sendMessage(text);
      if (!mounted) return;
      final short = reply.length > 80
          ? '${reply.substring(0, 80).trimRight()}…'
          : reply;
      setState(() {
        _uiState = RobotUiState.speaking;
        _subtitle = short;
      });
      await speak(reply);
    } catch (e) {
      if (mounted) {
        setState(() {
          _uiState = RobotUiState.error;
          _errorMessage = 'Backend không phản hồi.';
        });
      }
    }
  }

  @override
  void dispose() {
    _amplitudeSub?.cancel();
    _silenceTimer?.cancel();
    _recorder.dispose();
    super.dispose();
  }

  // ── Build ──────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final isLandscape = size.width > size.height;
    // orbSize: canvas = size * 1.45, phải fit trong viewport
    final orbSize = isLandscape
        ? size.height * 0.50   // landscape: 50% height — canvas chiếm ~72%
        : size.width * 0.62;   // portrait fallback

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Background
          const Positioned.fill(child: AnimatedBackground(state: RobotUiState.idle)),

          // Main content
          SafeArea(
            child: GestureDetector(
              onTap: _handleOrbTap,
              behavior: HitTestBehavior.translucent,
              child: _buildLayout(orbSize, isLandscape),
            ),
          ),

          // Settings icon — top right, very subtle
          Positioned(
            top: 10,
            right: 12,
            child: _settingsButton(),
          ),

          // MOCK badge — top left
          if (_isMockMode)
            const Positioned(
              top: 12,
              left: 12,
              child: _MockBadge(),
            ),
        ],
      ),
    );
  }

  Widget _buildLayout(double orbSize, bool isLandscape) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const SizedBox(height: 16),
        // Orb — centered, tap anywhere cycles state in mock mode
        Center(
          child: AiOrbWidget(state: _uiState, size: orbSize),
        ),
        const SizedBox(height: 12),
        // Status badge
        AiStatusBadge(state: _uiState),
        const SizedBox(height: 10),
        // Subtitle (only when speaking)
        if (_uiState.showSubtitle && _subtitle != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 40),
            child: AiSubtitlePanel(text: _subtitle, state: _uiState),
          ),
        // Error message
        if (_errorMessage != null)
          Padding(
            padding: const EdgeInsets.only(top: 8, left: 40, right: 40),
            child: Text(
              _errorMessage!,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Color(0xFFFF6B6B),
                fontSize: 13,
              ),
            ),
          ),
        const SizedBox(height: 12),
        // Tap hint — fades after 4 seconds
        AnimatedOpacity(
          opacity: _showHint ? 1.0 : 0.0,
          duration: const Duration(milliseconds: 800),
          child: Text(
            _isMockMode ? 'TAP TO CYCLE STATES' : 'TAP TO SPEAK',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.2),
              fontSize: 10,
              letterSpacing: 2.5,
            ),
          ),
        ),
        const SizedBox(height: 12),
      ],
    );
  }

  Widget _settingsButton() {
    return GestureDetector(
      onTap: _openSettings,
      child: Container(
        width: 30,
        height: 30,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white.withValues(alpha: 0.05),
          border: Border.all(
              color: Colors.white.withValues(alpha: 0.10), width: 0.8),
        ),
        child: Icon(
          Icons.settings_rounded,
          size: 14,
          color: Colors.white.withValues(alpha: 0.25),
        ),
      ),
    );
  }

  void _openSettings() {
    final ctrl = TextEditingController(text: ApiConfig.baseUrl);
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF080F1F),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: Colors.white.withValues(alpha: 0.10)),
        ),
        title: const Text(
          'Cài đặt',
          style: TextStyle(color: Colors.white, fontSize: 16),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Backend URL',
              style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.5), fontSize: 11),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: ctrl,
              style: const TextStyle(color: Colors.white, fontSize: 13),
              decoration: InputDecoration(
                hintText: 'http://192.168.x.x:8000',
                hintStyle: TextStyle(
                    color: Colors.white.withValues(alpha: 0.25),
                    fontSize: 13),
                enabledBorder: OutlineInputBorder(
                  borderSide: BorderSide(
                      color: Colors.white.withValues(alpha: 0.15)),
                  borderRadius: BorderRadius.circular(8),
                ),
                focusedBorder: OutlineInputBorder(
                  borderSide:
                      const BorderSide(color: Color(0xFF00B4FF)),
                  borderRadius: BorderRadius.circular(8),
                ),
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 10),
              ),
            ),
            const SizedBox(height: 12),
            // Mock / Live toggle
            Row(
              children: [
                const Text(
                  'Demo mode',
                  style: TextStyle(color: Colors.white54, fontSize: 12),
                ),
                const Spacer(),
                Switch(
                  value: _isMockMode,
                  activeThumbColor: const Color(0xFF00B4FF),
                  onChanged: (v) {
                    setState(() => _isMockMode = v);
                    Navigator.of(ctx).pop();
                  },
                ),
              ],
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child:
                const Text('Hủy', style: TextStyle(color: Colors.white38)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF00B4FF).withValues(alpha: 0.8),
              foregroundColor: Colors.black,
              elevation: 0,
            ),
            onPressed: () async {
              await ApiConfig.setBaseUrl(ctrl.text.trim());
              if (ctx.mounted) Navigator.of(ctx).pop();
            },
            child: const Text('Lưu',
                style: TextStyle(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }
}

class _MockBadge extends StatelessWidget {
  const _MockBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.amber.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: Colors.amber.withValues(alpha: 0.25)),
      ),
      child: const Text(
        'DEMO',
        style: TextStyle(
          color: Colors.amber,
          fontSize: 8,
          letterSpacing: 1.5,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
