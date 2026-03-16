import 'package:flutter/material.dart';

class MicGlow extends StatefulWidget {
  const MicGlow({super.key});

  @override
  State<MicGlow> createState() => _MicGlowState();
}

class _MicGlowState extends State<MicGlow>
    with SingleTickerProviderStateMixin {

  late AnimationController controller;

  @override
  void initState() {
    super.initState();

    controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {

    return AnimatedBuilder(
      animation: controller,
      builder: (context, child) {

        double size = 180 + controller.value * 40;

        return Container(
          width: size,
          height: size,

          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: const RadialGradient(
              colors: [
                Color(0xFF6EE7B7),
                Color(0xFF15803D),
              ],
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF34D399).withValues(alpha: 0.62),
                blurRadius: 40,
                spreadRadius: 20,
              )
            ],
          ),

          child: const Icon(
            Icons.mic,
            size: 60,
            color: Colors.white,
          ),
        );
      },
    );
  }
}