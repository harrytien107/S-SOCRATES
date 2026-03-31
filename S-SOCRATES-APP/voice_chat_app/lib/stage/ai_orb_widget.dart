import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import 'robot_ui_state.dart';
import 'ai_expression_model.dart';

// ─────────────────────────────────────────────────────────────────────────────
// AiOrbWidget — wireframe sphere + pseudo-face overlay
// ─────────────────────────────────────────────────────────────────────────────

class AiOrbWidget extends StatefulWidget {
  final RobotUiState state;
  final double size;

  const AiOrbWidget({super.key, required this.state, this.size = 280});

  @override
  State<AiOrbWidget> createState() => _AiOrbWidgetState();
}

class _AiOrbWidgetState extends State<AiOrbWidget>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  Duration _last = Duration.zero;

  // ── Sphere rotation ────────────────────────────────────────────
  double _outerAngleY = 0;
  double _innerAngleY = 0;

  // ── Pulse (0→1→0 continuous) ──────────────────────────────────
  double _pulse = 0;
  bool _pulseDir = true;

  // ── Expression smooth lerp ────────────────────────────────────
  // Start với idle expression
  AiExpressionData _currentExpr = kExpressions[RobotUiState.idle]!;

  // Speaking open/close cycle: 0 = closed, 1 = fully open
  double _speakCycle = 0;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_tick)..start();
  }

  void _tick(Duration elapsed) {
    if (!mounted) return;
    final dt = _last == Duration.zero
        ? 0.0
        : (elapsed - _last).inMicroseconds / 1e6;
    _last = elapsed;

    final s = widget.state;

    setState(() {
      // Sphere rotation
      _outerAngleY = (_outerAngleY + s.outerRotSpeed * dt) % (2 * math.pi);
      _innerAngleY = (_innerAngleY + s.innerRotSpeed * dt) % (2 * math.pi);

      // Pulse oscillation
      final pDelta = s.pulseSpeed * dt;
      if (_pulseDir) {
        _pulse += pDelta;
        if (_pulse >= 1) {
          _pulse = 1;
          _pulseDir = false;
        }
      } else {
        _pulse -= pDelta;
        if (_pulse <= 0) {
          _pulse = 0;
          _pulseDir = true;
        }
      }

      // Speaking mouth open/close cycle
      // abs(sin) → smooth 0→1→0→1→0 without sign change jump
      // 280ms per half-cycle ≈ natural speech rhythm
      _speakCycle = math.sin(elapsed.inMilliseconds / 280.0).abs();

      // Lerp expression toward target — speed depends on state urgency
      final target = kExpressions[s] ?? kExpressions[RobotUiState.idle]!;
      const lerpSpeed = 4.0; // ~0.25s to transition
      final t = (lerpSpeed * dt).clamp(0.0, 1.0);
      _currentExpr = _currentExpr.lerp(target, t);
    });
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final canvasSz = widget.size * 1.45;
    return SizedBox(
      width: canvasSz,
      height: canvasSz,
      child: CustomPaint(
        painter: _OrbWithFacePainter(
          outerAngleY: _outerAngleY,
          innerAngleY: _innerAngleY,
          pulse: _pulse,
          speakCycle: _speakCycle,
          state: widget.state,
          sphereRadius: widget.size / 2,
          expr: _currentExpr,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Combined Painter — sphere + face in one pass
// ─────────────────────────────────────────────────────────────────────────────

class _OrbWithFacePainter extends CustomPainter {
  final double outerAngleY;
  final double innerAngleY;
  final double pulse;
  final double speakCycle; // 0=closed 1=open, for speaking mouth
  final RobotUiState state;
  final double sphereRadius;
  final AiExpressionData expr;

  _OrbWithFacePainter({
    required this.outerAngleY,
    required this.innerAngleY,
    required this.pulse,
    required this.speakCycle,
    required this.state,
    required this.sphereRadius,
    required this.expr,
  });



  // ── 3D helpers ─────────────────────────────────────────────────
  List<double> _rotY(double x, double y, double z, double a) {
    final c = math.cos(a), s = math.sin(a);
    return [c * x + s * z, y, -s * x + c * z];
  }

  List<double> _rotX(double x, double y, double z, double a) {
    final c = math.cos(a), s = math.sin(a);
    return [x, c * y - s * z, s * y + c * z];
  }

  Offset _proj(double x, double y, double z, Offset ctr, double r) {
    const d = 3.5;
    final scale = d / (d + z * 0.25);
    return Offset(ctr.dx + x * r * scale, ctr.dy - y * r * scale);
  }

  double _depthAlpha(double z, double minA, double maxA) =>
      minA + (maxA - minA) * ((z + 1) / 2);

  // ── Main paint ─────────────────────────────────────────────────
  @override
  void paint(Canvas canvas, Size size) {
    final ctr = Offset(size.width / 2, size.height / 2);
    final outerR = sphereRadius;
    final color = state.primaryColor;

    // Ambient glow
    final glowAlpha = 0.20 + 0.15 * pulse;
    canvas.drawCircle(
      ctr,
      outerR * 1.35,
      Paint()
        ..shader = RadialGradient(
          colors: [
            color.withValues(alpha: glowAlpha),
            color.withValues(alpha: 0),
          ],
        ).createShader(Rect.fromCircle(center: ctr, radius: outerR * 1.35))
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 45),
    );

    // Outer lat/lon sphere
    _drawLatLon(canvas, ctr, outerR, outerAngleY, 0.0, color);

    // Face overlay — drawn last (on top)
    _drawFace(canvas, ctr, outerR, color);

    // Graduation Cap (UTH Personalization)
    _drawGraduationCap(canvas, ctr, outerR + 10, color);
  }

  // ── Lat/lon wireframe ──────────────────────────────────────────
  void _drawLatLon(
    Canvas canvas,
    Offset ctr,
    double r,
    double rotY,
    double tiltX,
    Color color,
  ) {
    const latN = 11;
    const lonN = 18;
    const pts = 60;

    // Latitude circles
    for (int i = 1; i < latN; i++) {
      final lat = -math.pi / 2 + i * math.pi / latN;
      final screenPts = <Offset>[];
      double sumZ = 0;

      for (int j = 0; j <= pts; j++) {
        final lon = j * 2 * math.pi / pts;
        final x0 = math.cos(lat) * math.cos(lon);
        final y0 = math.sin(lat);
        final z0 = math.cos(lat) * math.sin(lon);
        final r1 = _rotY(x0, y0, z0, rotY);
        final r2 = _rotX(r1[0], r1[1], r1[2], tiltX);
        sumZ += r2[2];
        screenPts.add(_proj(r2[0], r2[1], r2[2], ctr, r));
      }

      final avgZ = sumZ / (pts + 1);
      final alpha = _depthAlpha(avgZ, 0.12, 0.78);
      _drawPolyline(
        canvas,
        screenPts,
        color.withValues(alpha: alpha),
        avgZ > 0 ? 0.8 : 0.4,
      );
    }

    // Longitude meridians
    for (int i = 0; i < lonN; i++) {
      final lon = i * 2 * math.pi / lonN;
      final screenPts = <Offset>[];
      double sumZ = 0;

      for (int j = 0; j <= pts; j++) {
        final lat = -math.pi / 2 + j * math.pi / pts;
        final x0 = math.cos(lat) * math.cos(lon);
        final y0 = math.sin(lat);
        final z0 = math.cos(lat) * math.sin(lon);
        final r1 = _rotY(x0, y0, z0, rotY);
        final r2 = _rotX(r1[0], r1[1], r1[2], tiltX);
        sumZ += r2[2];
        screenPts.add(_proj(r2[0], r2[1], r2[2], ctr, r));
      }

      final avgZ = sumZ / (pts + 1);
      final alpha = _depthAlpha(avgZ, 0.10, 0.75);
      _drawPolyline(
        canvas,
        screenPts,
        color.withValues(alpha: alpha),
        avgZ > 0 ? 0.8 : 0.4,
      );
    }
  }

  void _drawPolyline(Canvas canvas, List<Offset> pts, Color color, double sw) {
    if (pts.length < 2) return;
    final path = Path()..moveTo(pts[0].dx, pts[0].dy);
    for (int i = 1; i < pts.length; i++) {
      path.lineTo(pts[i].dx, pts[i].dy);
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = sw
        ..isAntiAlias = true,
    );
  }

  // ── FACE OVERLAY ───────────────────────────────────────────────
  void _drawFace(Canvas canvas, Offset ctr, double R, Color color) {
    final e = expr;
    // ── Eye bars ─────────────────────────────────────────────────
    if (state == RobotUiState.uploading) {
      _drawThinkingWaveEye(
        canvas,
        center: Offset(
          ctr.dx - e.eyeSpread * R,
          ctr.dy + (e.eyeVertical + e.leftVOff) * R,
        ),
        hw: e.eyeHalfW * R,
        hh: e.eyeBarH * R,
        tilt: e.leftTilt,
        opacity: e.eyeOpacity,
        color: color,
        phase: innerAngleY * 1.8,
      );

      _drawThinkingWaveEye(
        canvas,
        center: Offset(
          ctr.dx + e.eyeSpread * R,
          ctr.dy + (e.eyeVertical + e.rightVOff) * R,
        ),
        hw: e.eyeHalfW * R,
        hh: e.eyeBarH * R,
        tilt: e.rightTilt,
        opacity: e.eyeOpacity,
        color: color,
        phase: innerAngleY * 1.8 + 0.7,
      );
    } else if (state == RobotUiState.thinking) {
      _drawRotatingCircleEye(
        canvas,
        center: Offset(
          ctr.dx - e.eyeSpread * R,
          ctr.dy + (e.eyeVertical + e.leftVOff) * R,
        ),
        radius: (e.eyeHalfW + e.eyeBarH) / 2 * R * 1.4,
        opacity: e.eyeOpacity,
        color: color,
        phase: innerAngleY * 2.5,
      );

      _drawRotatingCircleEye(
        canvas,
        center: Offset(
          ctr.dx + e.eyeSpread * R,
          ctr.dy + (e.eyeVertical + e.rightVOff) * R,
        ),
        radius: (e.eyeHalfW + e.eyeBarH) / 2 * R * 1.4,
        opacity: e.eyeOpacity,
        color: color,
        phase: innerAngleY * 2.5 + math.pi,
      );
    } else {
      double animHh = e.eyeBarH * R;
      if (state == RobotUiState.listening) {
        // Continuous blinking: sinusoidal variation between 0.1 and 1.0
        animHh *= (0.55 + 0.45 * math.sin(innerAngleY * 8));
      }

      _drawEye(
        canvas,
        center: Offset(
          ctr.dx - e.eyeSpread * R,
          ctr.dy + (e.eyeVertical + e.leftVOff) * R,
        ),
        hw: e.eyeHalfW * R,
        hh: animHh,
        tilt: e.leftTilt,
        opacity: e.eyeOpacity,
        color: color,
      );

      _drawEye(
        canvas,
        center: Offset(
          ctr.dx + e.eyeSpread * R,
          ctr.dy + (e.eyeVertical + e.rightVOff) * R,
        ),
        hw: e.eyeHalfW * R,
        hh: animHh,
        tilt: e.rightTilt,
        opacity: e.eyeOpacity,
        color: color,
      );
    }
    // ── Mouth ─────────────────────────────────────────────────────
    if (e.mouthOpacity > 0.01) {
      _drawMouth(canvas, ctr, R, color);
    }
  }

  void _drawThinkingWaveEye(
    Canvas canvas, {
    required Offset center,
    required double hw,
    required double hh,
    required double tilt,
    required double opacity,
    required Color color,
    required double phase,
  }) {
    if (opacity < 0.01 || hw < 1) return;

    final glowPaint = Paint()
      ..color = color.withValues(alpha: opacity * 0.50)
      ..style = PaintingStyle.stroke
      ..strokeWidth = hh * 0.95
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);

    final solidPaint = Paint()
      ..color = color.withValues(alpha: opacity)
      ..style = PaintingStyle.stroke
      ..strokeWidth = hh * 0.62
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..isAntiAlias = true;

    final path = Path();
    const int steps = 24;

    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(tilt);

    for (int i = 0; i <= steps; i++) {
      final t = i / steps;
      final x = -hw + t * hw * 2;

      // 2 gợn sóng nhẹ, không nên quá nhiều
      final y = math.sin(t * math.pi * 2.0 + phase) * hh * 0.55;

      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }

    canvas.drawPath(path, glowPaint);
    canvas.drawPath(path, solidPaint);

    canvas.restore();
  }

  void _drawEye(
    Canvas canvas, {
    required Offset center,
    required double hw,
    required double hh,
    required double tilt,
    required double opacity,
    required Color color,
  }) {
    if (opacity < 0.01 || hw < 1) return;

    final glowPaint = Paint()
      ..color = color.withValues(alpha: opacity * 0.55)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5);
    final solidPaint = Paint()
      ..color = color.withValues(alpha: opacity)
      ..style = PaintingStyle.fill;

    final rect = Rect.fromCenter(
      center: Offset.zero,
      width: hw * 2,
      height: hh * 2,
    );
    final rr = RRect.fromRectAndRadius(rect, Radius.circular(hh));

    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(tilt);

    canvas.drawRRect(rr, glowPaint);
    canvas.drawRRect(rr, solidPaint);

    canvas.restore();
  }

  void _drawRotatingCircleEye(
    Canvas canvas, {
    required Offset center,
    required double radius,
    required double opacity,
    required Color color,
    required double phase,
  }) {
    if (opacity < 0.01 || radius < 1) return;

    final glowPaint = Paint()
      ..color = color.withValues(alpha: opacity * 0.55)
      ..style = PaintingStyle.stroke
      ..strokeWidth = radius * 0.4
      ..strokeCap = StrokeCap.round
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5);

    final solidPaint = Paint()
      ..color = color.withValues(alpha: opacity)
      ..style = PaintingStyle.stroke
      ..strokeWidth = radius * 0.25
      ..strokeCap = StrokeCap.round
      ..isAntiAlias = true;

    final rect = Rect.fromCircle(center: center, radius: radius);

    // Draw an arc from phase to phase + PI*1.5
    final startAngle = phase;
    final sweepAngle = math.pi * 1.5;

    canvas.drawArc(rect, startAngle, sweepAngle, false, glowPaint);
    canvas.drawArc(rect, startAngle, sweepAngle, false, solidPaint);
  }

  // ── GRADUATION CAP (UTH) ───────────────────────────────────────────────
  void _drawGraduationCap(Canvas canvas, Offset ctr, double R, Color color) {
    // Hover effect based on pulse
    final bounceY = math.sin(pulse * math.pi * 2) * R * 0.025;
    final cy = ctr.dy - R * 0.98 + bounceY; 
    final cx = ctr.dx;

    final glowPaint = Paint()
      ..color = color.withValues(alpha: 0.50)
      ..style = PaintingStyle.stroke
      ..strokeWidth = R * 0.025
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5);

    final solidPaint = Paint()
      ..color = color.withValues(alpha: 0.90)
      ..style = PaintingStyle.stroke
      ..strokeWidth = R * 0.012
      ..isAntiAlias = true;

    // Mortarboard (Diamond / Rhombus projection)
    final boardW = R * 0.65;
    final boardH = R * 0.20;
    
    final boardPath = Path()
      ..moveTo(cx, cy - boardH) // top
      ..lineTo(cx + boardW, cy) // right
      ..lineTo(cx, cy + boardH) // bottom
      ..lineTo(cx - boardW, cy) // left
      ..close();

    // Base (Skull cap)
    final baseW = R * 0.35;
    final baseTopY = cy + boardH * 0.53; // slightly below center
    final baseBotY = cy + boardH * 1.8;

    final basePath = Path()
      ..moveTo(cx - baseW, baseTopY)
      ..lineTo(cx - baseW, baseBotY)
      // bottom curve
      ..quadraticBezierTo(cx, baseBotY + R * 0.12, cx + baseW, baseBotY)
      ..lineTo(cx + baseW, baseTopY);

    // Tassel
    final tasselPath = Path()
      ..moveTo(cx, cy) // center knot
      // droop down to the right
      ..quadraticBezierTo(cx + boardW * 0.4, cy + boardH * 0.5, cx + boardW * 0.85, cy + boardH * 2.2);

    // Draw lines
    for (final p in [glowPaint, solidPaint]) {
      canvas.drawPath(boardPath, p);
      canvas.drawPath(basePath, p);
      canvas.drawPath(tasselPath, p);
      
      // Center knot
      canvas.drawCircle(Offset(cx, cy), R * 0.02, Paint()..color = p.color ..style=PaintingStyle.fill);
      // Tassel fringe
      canvas.drawCircle(Offset(cx + boardW * 0.85, cy + boardH * 2.2), R * 0.03, Paint()..color = p.color ..style=PaintingStyle.fill);
    }

    // "UTH" text on cap base
    final textSpan = TextSpan(
      text: 'UTH',
      style: TextStyle(
        color: color.withValues(alpha: 0.85),
        fontSize: R * 0.16,
        fontWeight: FontWeight.w900,
        letterSpacing: 2.0,
        shadows: [
          Shadow(
            color: color,
            blurRadius: 6.0,
          )
        ]
      ),
    );
    final textPainter = TextPainter(
      text: textSpan,
      textDirection: TextDirection.ltr,
    );
    textPainter.layout();
    final textX = cx - textPainter.width / 2;
    final textY = baseBotY - textPainter.height * 0.85;
    textPainter.paint(canvas, Offset(textX, textY));
  }

  void _drawMouth(Canvas canvas, Offset ctr, double R, Color color) {
    final e = expr;
    final hw = e.mouthHalfW * R;
    final vy = ctr.dy + e.mouthVertical * R;

    final dynamicThickness =
        e.mouthThickness +
        (state == RobotUiState.speaking ? 0.008 * speakCycle : 0.0);

    final glowPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = R * dynamicThickness * 2
      ..strokeCap = StrokeCap.round
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);

    final solidPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = R * dynamicThickness
      ..strokeCap = StrokeCap.round
      ..isAntiAlias = true;

    if (e.mouthBroken) {
      // Error: broken dashed segments
      glowPaint.color = color.withValues(alpha: e.mouthOpacity * 0.45);
      solidPaint.color = color.withValues(alpha: e.mouthOpacity);
      _drawBrokenMouth(
        canvas,
        Offset(ctr.dx - hw, vy),
        Offset(ctr.dx + hw, vy),
        glowPaint,
        solidPaint,
      );
      return;
    }

    if (state == RobotUiState.speaking) {
      // ── SPEAKING: open/close arch ──────────────────────────────
      // speakCycle: 0=closed 1=fully open (abs sin → smooth cycle)
      //
      // Arch = ellipse arc from leftPt to rightPt curving DOWN
      // (mouth opens downward like a real mouth)
      // maxOpenHeight controls how wide the arch gets
      const double maxOpenH = 0.12; // fraction of R — tăng để mở rộng hơn
      final openH = speakCycle * maxOpenH * R;

      glowPaint.color = color.withValues(alpha: e.mouthOpacity * 0.55);
      solidPaint.color = color.withValues(alpha: e.mouthOpacity);

      _drawSpeakArch(
        canvas,
        ctr: ctr,
        hw: hw,
        vy: vy,
        openH: openH,
        skew: e.mouthSkew * R,
        glowPaint: glowPaint,
        solidPaint: solidPaint,
      );
    } else {
      // ── OTHER STATES: smooth bezier smile/frown ────────────────
      final cpY = vy + e.mouthCurve * R * 0.28;
      final cpX = ctr.dx + e.mouthSkew * R;

      glowPaint.color = color.withValues(alpha: e.mouthOpacity * 0.50);
      solidPaint.color = color.withValues(alpha: e.mouthOpacity);

      final path = Path()
        ..moveTo(ctr.dx - hw, vy)
        ..quadraticBezierTo(cpX, cpY, ctr.dx + hw, vy);
      canvas.drawPath(path, glowPaint);
      canvas.drawPath(path, solidPaint);
    }
  }

  /// Vẽ arch mở miệng: upper arc (smile fixed) + lower arc (opens/closes)
  void _drawSpeakArch(
    Canvas canvas, {
    required Offset ctr,
    required double hw,
    required double vy,
    required double openH, // current open height (0=closed)
    required double skew,
    required Paint glowPaint,
    required Paint solidPaint,
  }) {
    // Upper lip: fixed gentle smile arc
    const double upperCurve = 0.06; // slight upward bow
    final upperCpY = vy - upperCurve * hw;
    final upperPath = Path()
      ..moveTo(ctr.dx - hw, vy)
      ..quadraticBezierTo(ctr.dx + skew, upperCpY, ctr.dx + hw, vy);

    // Lower lip: opens downward proportional to speakCycle
    // When openH=0 → collapses onto upper lip (closed)
    // When openH=max → visibly open gap below
    final lowerCpY = vy + openH;
    final lowerPath = Path()
      ..moveTo(ctr.dx - hw, vy)
      ..quadraticBezierTo(ctr.dx + skew, lowerCpY, ctr.dx + hw, vy);

    canvas.drawPath(upperPath, glowPaint);
    canvas.drawPath(upperPath, solidPaint);

    // Only draw lower lip when noticeably open
    if (openH > 1.5) {
      canvas.drawPath(lowerPath, glowPaint);
      canvas.drawPath(lowerPath, solidPaint);
    }
  }

  /// Broken/glitch mouth for error state — dashed segments with slight offsets
  static const List<double> _brokenOffsets = [2.0, -3.0, 1.5, -2.5];

  void _drawBrokenMouth(
    Canvas canvas,
    Offset left,
    Offset right,
    Paint glowP,
    Paint solidP,
  ) {
    final totalW = right.dx - left.dx;
    const segCount = 4;
    final segW = totalW / (segCount * 2 - 1);

    for (int i = 0; i < segCount; i++) {
      final x0 = left.dx + i * segW * 2;
      final x1 = x0 + segW * 0.75;
      final yOff = _brokenOffsets[i];
      final p0 = Offset(x0, left.dy + yOff);
      final p1 = Offset(x1, left.dy + yOff);
      canvas.drawLine(p0, p1, glowP);
      canvas.drawLine(p0, p1, solidP);
    }
  }

  @override
  bool shouldRepaint(_OrbWithFacePainter old) =>
      old.outerAngleY != outerAngleY ||
      old.innerAngleY != innerAngleY ||
      old.pulse != pulse ||
      old.speakCycle != speakCycle ||
      old.state != state ||
      old.expr != expr;
}
