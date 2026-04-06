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
    final orbSize = isLandscape
        ? size.height * 0.66
        : size.width * 0.78;

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

          SafeArea(
            child: IgnorePointer(
              child: Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: isLandscape ? 22 : 16,
                  vertical: isLandscape ? 18 : 14,
                ),
                child: Column(
                  children: [
                    _buildBrandHeader(isLandscape),
                    const Spacer(),
                  ],
                ),
              ),
            ),
          ),

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
        SizedBox(height: isLandscape ? 10 : 20),
        Center(
          child: AiOrbWidget(state: _uiState, size: orbSize),
        ),
      ],
    );
  }

  Widget _buildBrandHeader(bool isLandscape) {
    final logoHeight = isLandscape ? 46.0 : 34.0;

    return Align(
      alignment: Alignment.topLeft,
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: isLandscape ? 10 : 8,
          vertical: isLandscape ? 8 : 6,
        ),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          color: Colors.white.withValues(alpha: 0.92),
          border: Border.all(
            color: const Color(0xFF0CD2DA).withValues(alpha: 0.16),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.16),
              blurRadius: 18,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Image.asset(
          'assets/logo_full.png',
          height: logoHeight,
          fit: BoxFit.contain,
          filterQuality: FilterQuality.high,
        ),
      ),
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
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final mediaQuery = MediaQuery.of(ctx);

        return SafeArea(
          child: AnimatedPadding(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOut,
            padding: EdgeInsets.only(
              left: 14,
              right: 14,
              bottom: mediaQuery.viewInsets.bottom + 14,
              top: 14,
            ),
            child: Align(
              alignment: Alignment.bottomCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: Material(
                  color: const Color(0xFF080F1F),
                  borderRadius: BorderRadius.circular(24),
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(18, 14, 18, 18),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.10),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.32),
                          blurRadius: 26,
                          offset: const Offset(0, 12),
                        ),
                      ],
                    ),
                    child: SingleChildScrollView(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Center(
                            child: Container(
                              width: 46,
                              height: 5,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(999),
                                color: Colors.white.withValues(alpha: 0.16),
                              ),
                            ),
                          ),
                          const SizedBox(height: 14),
                          const Text(
                            'Cài đặt kết nối',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Nhập địa chỉ backend để robot kết nối ổn định với server.',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.58),
                              fontSize: 12.5,
                              height: 1.35,
                            ),
                          ),
                          const SizedBox(height: 18),
                          Text(
                            'Backend URL',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.62),
                              fontSize: 11.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 8),
                          TextField(
                            controller: ctrl,
                            autofocus: true,
                            keyboardType: TextInputType.url,
                            textInputAction: TextInputAction.done,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                            ),
                            decoration: InputDecoration(
                              hintText: 'http://192.168.x.x:8000',
                              hintStyle: TextStyle(
                                color: Colors.white.withValues(alpha: 0.25),
                                fontSize: 13,
                              ),
                              filled: true,
                              fillColor: Colors.white.withValues(alpha: 0.04),
                              enabledBorder: OutlineInputBorder(
                                borderSide: BorderSide(
                                  color: Colors.white.withValues(alpha: 0.15),
                                ),
                                borderRadius: BorderRadius.circular(14),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderSide: const BorderSide(
                                  color: Color(0xFF00B4FF),
                                  width: 1.2,
                                ),
                                borderRadius: BorderRadius.circular(14),
                              ),
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 14,
                              ),
                            ),
                            onSubmitted: (_) async {
                              await ApiConfig.setBaseUrl(ctrl.text.trim());
                              await _robotController.refreshBackendStatus();
                              if (ctx.mounted) Navigator.of(ctx).pop();
                            },
                          ),
                          const SizedBox(height: 18),
                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton(
                                  style: OutlinedButton.styleFrom(
                                    side: BorderSide(
                                      color: Colors.white.withValues(alpha: 0.12),
                                    ),
                                    foregroundColor: Colors.white70,
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 14,
                                    ),
                                  ),
                                  onPressed: () => Navigator.of(ctx).pop(),
                                  child: const Text('Hủy'),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: ElevatedButton(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFF00B4FF)
                                        .withValues(alpha: 0.86),
                                    foregroundColor: Colors.black,
                                    elevation: 0,
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 14,
                                    ),
                                  ),
                                  onPressed: () async {
                                    await ApiConfig.setBaseUrl(ctrl.text.trim());
                                    await _robotController.refreshBackendStatus();
                                    if (ctx.mounted) Navigator.of(ctx).pop();
                                  },
                                  child: const Text(
                                    'Lưu',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
