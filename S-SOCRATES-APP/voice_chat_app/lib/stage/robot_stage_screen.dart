import 'dart:async';
import 'package:flutter/material.dart';
import 'robot_ui_state.dart';
import 'animated_background.dart';
import 'ai_orb_widget.dart';
import '../services/api_config.dart';
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

  // ── Services ──────────────────────────────────────────────────
  final RobotController _robotController = RobotController();

  // ── Mock / demo (removed) ──────────────────────────────────────

  // ── Audio Capture State ────────────────────────────────────────
  bool _isRecording = false;

  // ── Hint "tap" label ──────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _setupController();
  }

  void _setupController() {
    void syncUiState() {
      if (!mounted) return;
      final backendReachable = _robotController.isBackendReachable.value;
      final newState = backendReachable
          ? _robotController.state.value
          : RobotUiState.error;
      setState(() {
        _uiState = newState;
        _isRecording = newState == RobotUiState.listening;
      });
    }

    _robotController.state.addListener(syncUiState);
    _robotController.isBackendReachable.addListener(syncUiState);

    _robotController.startPolling();
  }

  // ── Tap orb ───────────────────────────────────────────────────
  Future<void> _handleOrbTap() async {
    // Nếu đang nói, suy nghĩ, đang upload, hoặc đang lỗi (mất kết nối) thì bỏ qua
    if (_uiState == RobotUiState.thinking ||
        _uiState == RobotUiState.speaking ||
        _uiState == RobotUiState.uploading ||
        _uiState == RobotUiState.error) {
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
    await _robotController.manualStartRecording();
  }

  Future<void> _stopRecording() async {
    setState(() {
      _isRecording = false;
      _uiState = RobotUiState.uploading;
    });
    await _robotController.manualStopRecording();
  }

  @override
  void dispose() {
    // Hide stale connection notice when leaving this screen.
    _robotController.clearConnectionWarning();
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

          // Settings icon — top right, only on error
          if (_uiState == RobotUiState.error)
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
              await _robotController.refreshBackendStatus();
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
