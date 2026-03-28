import 'dart:async';
import 'package:flutter/material.dart';
import 'robot_ui_state.dart';
import 'animated_background.dart';
import 'ai_orb_widget.dart';
import 'ai_status_badge.dart';
import 'ai_subtitle_panel.dart';
import '../services/api_config.dart';
import '../services/tts_service.dart';
import '../controllers/robot_controller.dart';

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
  final RobotController _robotController = RobotController();

  // ── Mock / demo (removed) ──────────────────────────────────────

  // ── Audio Capture State ────────────────────────────────────────
  bool _isRecording = false;

  // ── Hint "tap" label ──────────────────────────────────────────
  bool _showHint = true;

  @override
  void initState() {
    super.initState();
    _setupController();

    // Hide tap hint after 4 seconds
    Future.delayed(const Duration(seconds: 4), () {
      if (mounted) setState(() => _showHint = false);
    });
  }

  void _setupController() {
    _robotController.state.addListener(() {
      if (mounted) {
        setState(() => _uiState = _robotController.state.value);
      }
    });

    _robotController.currentMessage.addListener(() {
      if (mounted) {
        final text = _robotController.currentMessage.value;
        setState(() {
          _subtitle = text.length > 80 ? '${text.substring(0, 80)}…' : text;
          if (text.isEmpty) _subtitle = null;
        });
      }
    });

    _robotController.startPolling();
  }

  // ── Tap orb ───────────────────────────────────────────────────
  Future<void> _handleOrbTap() async {
    setState(() => _showHint = false);
    
    // Nếu đang nói hoặc suy nghĩ thì bỏ qua
    if (_uiState == RobotUiState.thinking || _uiState == RobotUiState.speaking || _uiState == RobotUiState.uploading) {
        return;
    }

    if (!_isRecording) {
      await _startRecording();
    } else {
      await _stopRecording();
    }
  }

  Future<void> _startRecording() async {
    setState(() {
        _isRecording = true;
        _uiState = RobotUiState.listening;
    });
    // Gọi controller để bắt đầu ghi âm
    await _robotController.startRecordingAudio();
  }

  Future<void> _stopRecording() async {
    setState(() {
        _isRecording = false;
        _uiState = RobotUiState.uploading;
    });
    // Gọi controller để dừng ghi âm và gửi backend
    await _robotController.stopRecordingAndProcess();
  }

  @override
  void dispose() {
    _robotController.dispose();
    super.dispose();
  }

  // ── Build ──────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final isLandscape = size.width > size.height;
    // orbSize: canvas = size * 1.45, phải fit trong viewport
    final orbSize = isLandscape
        ? size.height *
              0.50 // landscape: 50% height — canvas chiếm ~72%
        : size.width * 0.62; // portrait fallback

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Background
          const Positioned.fill(
            child: AnimatedBackground(state: RobotUiState.idle),
          ),

          // Main content
          SafeArea(
            child: GestureDetector(
              onTap: _handleOrbTap,
              behavior: HitTestBehavior.translucent,
              child: _buildLayout(orbSize, isLandscape),
            ),
          ),

          // Settings icon — top right, very subtle
          Positioned(top: 10, right: 12, child: _settingsButton()),
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
              style: const TextStyle(color: Color(0xFFFF6B6B), fontSize: 13),
            ),
          ),
        const SizedBox(height: 12),
        // Tap hint — fades after 4 seconds
        AnimatedOpacity(
          opacity: _showHint ? 1.0 : 0.0,
          duration: const Duration(milliseconds: 800),
          child: Text(
            'POLLING LIVE COMMANDS...',
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
            color: Colors.white.withValues(alpha: 0.10),
            width: 0.8,
          ),
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
                color: Colors.white.withValues(alpha: 0.5),
                fontSize: 11,
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: ctrl,
              style: const TextStyle(color: Colors.white, fontSize: 13),
              decoration: InputDecoration(
                hintText: 'http://192.168.x.x:8000',
                hintStyle: TextStyle(
                  color: Colors.white.withValues(alpha: 0.25),
                  fontSize: 13,
                ),
                enabledBorder: OutlineInputBorder(
                  borderSide: BorderSide(
                    color: Colors.white.withValues(alpha: 0.15),
                  ),
                  borderRadius: BorderRadius.circular(8),
                ),
                focusedBorder: OutlineInputBorder(
                  borderSide: const BorderSide(color: Color(0xFF00B4FF)),
                  borderRadius: BorderRadius.circular(8),
                ),
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
              ),
            ),
            const SizedBox(height: 12),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Hủy', style: TextStyle(color: Colors.white38)),
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
            child: const Text(
              'Lưu',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
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
