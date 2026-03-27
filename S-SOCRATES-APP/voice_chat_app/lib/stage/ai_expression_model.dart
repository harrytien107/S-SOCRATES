/// Expression data model — định nghĩa biểu cảm mặt giả trên sphere
///
/// Tất cả giá trị là fraction của sphereRadius để scale tự động
library;

import 'robot_ui_state.dart';

class AiExpressionData {
  final double eyeHalfW;
  final double eyeBarH;
  final double eyeSpread;
  final double eyeVertical;

  final double leftTilt;
  final double rightTilt;
  final double leftVOff;
  final double rightVOff;
  final double eyeOpacity;

  final double mouthHalfW;
  final double mouthVertical;

  /// +1 = smile, -1 = frown, 0 = flat
  final double mouthCurve;

  /// lệch tâm control point để tạo smirk / mischievous
  final double mouthSkew;

  /// độ mở miệng (0 = line, 1 = mở lớn)
  final double mouthOpen;

  /// độ dày nét miệng
  final double mouthThickness;

  final double mouthOpacity;
  final bool mouthBroken;

  const AiExpressionData({
    this.eyeHalfW = 0.18,
    this.eyeBarH = 0.028,
    this.eyeSpread = 0.26,
    this.eyeVertical = -0.22,
    this.leftTilt = 0,
    this.rightTilt = 0,
    this.leftVOff = 0,
    this.rightVOff = 0,
    this.eyeOpacity = 0.9,
    this.mouthHalfW = 0.18,
    this.mouthVertical = 0.18,
    this.mouthCurve = 0,
    this.mouthSkew = 0,
    this.mouthOpen = 0,
    this.mouthThickness = 0.02,
    this.mouthOpacity = 0.65,
    this.mouthBroken = false,
  });

  AiExpressionData lerp(AiExpressionData b, double t) {
    double l(double a, double x) => a + (x - a) * t;
    return AiExpressionData(
      eyeHalfW: l(eyeHalfW, b.eyeHalfW),
      eyeBarH: l(eyeBarH, b.eyeBarH),
      eyeSpread: l(eyeSpread, b.eyeSpread),
      eyeVertical: l(eyeVertical, b.eyeVertical),
      leftTilt: l(leftTilt, b.leftTilt),
      rightTilt: l(rightTilt, b.rightTilt),
      leftVOff: l(leftVOff, b.leftVOff),
      rightVOff: l(rightVOff, b.rightVOff),
      eyeOpacity: l(eyeOpacity, b.eyeOpacity).clamp(0.0, 1.0),
      mouthHalfW: l(mouthHalfW, b.mouthHalfW),
      mouthVertical: l(mouthVertical, b.mouthVertical),
      mouthCurve: l(mouthCurve, b.mouthCurve).clamp(-1.0, 1.0),
      mouthSkew: l(mouthSkew, b.mouthSkew),
      mouthOpen: l(mouthOpen, b.mouthOpen).clamp(0.0, 1.0),
      mouthThickness: l(mouthThickness, b.mouthThickness).clamp(0.0, 1.0),
      mouthOpacity: l(mouthOpacity, b.mouthOpacity).clamp(0.0, 1.0),
      mouthBroken: b.mouthBroken,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Presets theo state — chỉnh nhanh ở đây
// ─────────────────────────────────────────────────────────────────────────────

const Map<RobotUiState, AiExpressionData> kExpressions = {
  // Vào app là thấy robot thân thiện, vui vẻ
  RobotUiState.idle: AiExpressionData(
    eyeHalfW: 0.11,
    eyeBarH: 0.040,
    eyeSpread: 0.27,
    eyeVertical: -0.20,
    leftVOff: 0.008,
    rightVOff: 0.008,
    eyeOpacity: 0.98,
    mouthHalfW: 0.23,
    mouthVertical: 0.10,
    mouthCurve: 0.65,
    mouthOpen: 0.10,
    mouthThickness: 0.018,
    mouthOpacity: 1.0,
  ),

  // Chăm chú lắng nghe
  RobotUiState.listening: AiExpressionData(
    eyeHalfW: 0.15,
    eyeBarH: 0.10,
    eyeSpread: 0.29,
    eyeVertical: -0.23,
    eyeOpacity: 0.96,
    mouthHalfW: 0.11,
    mouthVertical: 0.18,
    mouthCurve: 0,
    mouthOpen: 0.02,
    mouthThickness: 0.02,
    mouthOpacity: 0.3,
  ),

  // Suy nghĩ
  RobotUiState.thinking: AiExpressionData(
    eyeHalfW: 0.14,
    eyeBarH: 0.020,
    eyeSpread: 0.23,
    eyeVertical: -0.21,
    leftTilt: -0.03,
    rightTilt: 0.03,
    eyeOpacity: 0.9,
    mouthHalfW: 0.10,
    mouthVertical: 0.19,
    mouthCurve: 0,
    mouthOpen: 0.00,
    mouthThickness: 0.012,
    mouthOpacity: 0.3,
  ),

  // Nói: base shape trung tính, animate bằng mouthOpen
  RobotUiState.speaking: AiExpressionData(
    eyeHalfW: 0.12,
    eyeBarH: 0.032,
    eyeSpread: 0.26,
    eyeVertical: -0.21,
    eyeOpacity: 0.92,
    mouthHalfW: 0.20,
    mouthVertical: 0.16,
    mouthCurve: 0.10,
    mouthOpen: 0.35,
    mouthThickness: 0.020,
    mouthOpacity: 0.95,
  ),

  // Tinh nghịch / thách thức
  RobotUiState.challenge: AiExpressionData(
    eyeHalfW: 0.14,
    eyeBarH: 0.024,
    eyeSpread: 0.26,
    eyeVertical: -0.22,
    leftTilt: -0.10,
    rightTilt: 0.16,
    leftVOff: 0.012,
    rightVOff: -0.030,
    eyeOpacity: 0.98,
    mouthHalfW: 0.18,
    mouthVertical: 0.17,
    mouthCurve: 0.32,
    mouthSkew: 0.07,
    mouthOpen: 0.06,
    mouthThickness: 0.018,
    mouthOpacity: 0.92,
  ),

  // Lỗi
  RobotUiState.error: AiExpressionData(
    eyeHalfW: 0.10,
    eyeBarH: 0.012,
    eyeSpread: 0.24,
    eyeVertical: -0.21,
    eyeOpacity: 0.22,
    mouthHalfW: 0.16,
    mouthVertical: 0.19,
    mouthCurve: -0.18,
    mouthOpen: 0.00,
    mouthThickness: 0.015,
    mouthOpacity: 0.40,
    mouthBroken: true,
  ),
};