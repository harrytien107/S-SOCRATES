import 'package:flutter/material.dart';

import 'robot_ui_state.dart';

/// Panel subtitle hiển thị tối đa 2 dòng khi AI đang nói
class AiSubtitlePanel extends StatelessWidget {
  final String? text;
  final RobotUiState state;

  const AiSubtitlePanel({
    super.key,
    required this.text,
    required this.state,
  });

  @override
  Widget build(BuildContext context) {
    final visible = state.showSubtitle && text != null && text!.isNotEmpty;
    final color = state.primaryColor;

    return AnimatedOpacity(
      opacity: visible ? 1.0 : 0.0,
      duration: const Duration(milliseconds: 500),
      curve: Curves.easeInOut,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 350),
        transitionBuilder: (child, anim) => FadeTransition(
          opacity: anim,
          child: child,
        ),
        child: visible
            ? Container(
                key: ValueKey(text),
                constraints: const BoxConstraints(maxWidth: 720),
                padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.45),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: color.withValues(alpha: 0.22),
                    width: 1,
                  ),
                ),
                child: Text(
                  text!,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.92),
                    fontSize: 22,
                    fontWeight: FontWeight.w500,
                    height: 1.45,
                    letterSpacing: 0.2,
                    shadows: [
                      Shadow(
                        color: color.withValues(alpha: 0.4),
                        blurRadius: 16,
                      ),
                    ],
                  ),
                ),
              )
            : const SizedBox(key: ValueKey('empty'), height: 0),
      ),
    );
  }
}
