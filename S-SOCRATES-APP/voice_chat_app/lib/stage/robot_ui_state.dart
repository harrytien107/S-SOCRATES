import 'package:flutter/material.dart';

/// Trạng thái của AI robot trên sân khấu
enum RobotUiState { idle, listening, thinking, speaking, challenge, error }

extension RobotUiStateX on RobotUiState {
  String get label {
    switch (this) {
      case RobotUiState.idle:
        return 'Sẵn sàng';
      case RobotUiState.listening:
        return 'Đang lắng nghe';
      case RobotUiState.thinking:
        return 'Đang suy nghĩ';
      case RobotUiState.speaking:
        return 'S-Socrates đang phản biện';
      case RobotUiState.challenge:
        return 'Thách thức!';
      case RobotUiState.error:
        return 'Mất kết nối';
    }
  }

  Color get primaryColor {
    switch (this) {
      case RobotUiState.idle:
        return const Color(0xFF00B4FF);
      case RobotUiState.listening:
        return const Color(0xFF00FFCC);
      case RobotUiState.thinking:
        return const Color(0xFF4488FF);
      case RobotUiState.speaking:
        return const Color(0xFF00EEFF);
      case RobotUiState.challenge:
        return const Color(0xFFFF6B35);
      case RobotUiState.error:
        return const Color(0xFFFF4455);
    }
  }

  Color get glowColor {
    return primaryColor.withValues(alpha: 0.4);
  }

  /// Outer sphere Y rotation speed (radians/second)
  double get outerRotSpeed {
    switch (this) {
      case RobotUiState.idle:
        return 0.20;
      case RobotUiState.listening:
        return 0.55;
      case RobotUiState.thinking:
        return 0.80;
      case RobotUiState.speaking:
        return 0.40;
      case RobotUiState.challenge:
        return 1.10;
      case RobotUiState.error:
        return 0.08;
    }
  }

  /// Inner icosphere rotation speed (slightly faster, different axis feel)
  double get innerRotSpeed {
    switch (this) {
      case RobotUiState.idle:
        return 0.32;
      case RobotUiState.listening:
        return 0.75;
      case RobotUiState.thinking:
        return 1.20;
      case RobotUiState.speaking:
        return 0.60;
      case RobotUiState.challenge:
        return 1.50;
      case RobotUiState.error:
        return 0.10;
    }
  }

  /// Pulse oscillation speed (1/second)
  double get pulseSpeed {
    switch (this) {
      case RobotUiState.idle:
        return 0.40;
      case RobotUiState.listening:
        return 1.20;
      case RobotUiState.thinking:
        return 0.90;
      case RobotUiState.speaking:
        return 0.70;
      case RobotUiState.challenge:
        return 1.60;
      case RobotUiState.error:
        return 0.25;
    }
  }

  bool get showSubtitle => this == RobotUiState.speaking || this == RobotUiState.challenge;
}

/// Mock subtitles cho demo mode
const List<String> kMockSubtitles = [
  'Thưa Giáo sư, em không over-thinking đâu, nhưng...',
  'Quan điểm này rất hay, cơ mà em thấy hơi lấn cấn ạ.',
  'Nếu AI làm nhanh hơn con người, vậy điều gì còn là bản sắc?',
  'Bằng chứng nào cho thấy điều đó là đúng hoàn toàn?',
  'Đây là một paradox thú vị — và tôi không đồng ý.',
  'Logic này bắt đầu lung lay khi áp vào thực tế.',
];

const String kMockErrorMessage =
    'Mất kết nối backend. Kiểm tra IP và thử lại.';
