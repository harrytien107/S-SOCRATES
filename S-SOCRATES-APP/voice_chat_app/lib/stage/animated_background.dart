import 'package:flutter/material.dart';

import 'robot_ui_state.dart';

/// Nền tối giản dark navy — không grid, chỉ có glow nhẹ ở center
class AnimatedBackground extends StatelessWidget {
  final RobotUiState state;

  const AnimatedBackground({super.key, required this.state});

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment(0, -0.1),
            radius: 1.2,
            colors: [
              Color(0xFF080F1F), // center: dark navy slightly lighter
              Color(0xFF030813), // outer: near black
            ],
          ),
        ),
      ),
    );
  }
}
