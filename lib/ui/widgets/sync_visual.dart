import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import '../theme/app_theme.dart';

class SyncOrbit extends StatefulWidget {
  const SyncOrbit({
    super.key,
    this.size = 220,
    this.active = false,
    this.deviceCount = 0,
  });

  final double size;
  final bool active;
  final int deviceCount;

  @override
  State<SyncOrbit> createState() => _SyncOrbitState();
}

class _SyncOrbitState extends State<SyncOrbit> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 14),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          return CustomPaint(
            painter: _OrbitPainter(
              progress: _controller.value,
              active: widget.active,
              deviceCount: widget.deviceCount,
            ),
          );
        },
      ),
    );
  }
}

class _OrbitPainter extends CustomPainter {
  _OrbitPainter({
    required this.progress,
    required this.active,
    required this.deviceCount,
  });

  final double progress;
  final bool active;
  final int deviceCount;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.shortestSide * 0.36;

    final orbitPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = AppColors.paper.withValues(alpha: active ? 0.2 : 0.12);

    canvas.drawCircle(center, radius, orbitPaint);
    canvas.drawCircle(
      center,
      radius * 0.66,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = AppColors.paper.withValues(alpha: 0.08),
    );

    for (var i = 0; i < 28; i++) {
      final angle = (i / 28) * math.pi * 2;
      final dotCenter = Offset(
        center.dx + math.cos(angle) * radius,
        center.dy + math.sin(angle) * radius,
      );
      canvas.drawCircle(
        dotCenter,
        1.1,
        Paint()..color = AppColors.paper.withValues(alpha: i.isEven ? 0.22 : 0.07),
      );
    }

    final nodes = math.max(1, math.min(3, deviceCount == 0 ? 1 : deviceCount));
    final nodeColors = <Color>[AppColors.lime, AppColors.coral, AppColors.sky];
    for (var i = 0; i < nodes; i++) {
      final base = (i / nodes) * math.pi * 2 - math.pi / 2;
      final angle = base + progress * math.pi * 2 * 0.08;
      final nodeRadius = radius * (i == 0 ? 1.0 : 0.82);
      final position = Offset(
        center.dx + math.cos(angle) * nodeRadius,
        center.dy + math.sin(angle) * nodeRadius,
      );
      if (active) {
        canvas.drawLine(
          center,
          position,
          Paint()
            ..color = nodeColors[i % nodeColors.length].withValues(alpha: 0.18)
            ..strokeWidth = 1.2,
        );
      }
      canvas.drawCircle(
        position,
        12,
        Paint()..color = nodeColors[i % nodeColors.length].withValues(alpha: 0.16),
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(center: position, width: 18, height: 23),
          const Radius.circular(5),
        ),
        Paint()..color = nodeColors[i % nodeColors.length],
      );
      canvas.drawLine(
        position + const Offset(-4, 3),
        position + const Offset(4, 3),
        Paint()
          ..color = AppColors.ink.withValues(alpha: 0.55)
          ..strokeWidth = 1.3
          ..strokeCap = StrokeCap.round,
      );
      canvas.drawLine(
        position + const Offset(-4, 7),
        position + const Offset(1, 7),
        Paint()
          ..color = AppColors.ink.withValues(alpha: 0.55)
          ..strokeWidth = 1.3
          ..strokeCap = StrokeCap.round,
      );
    }

    final centerGlow = Paint()
      ..shader = RadialGradient(
        colors: <Color>[
          AppColors.lime.withValues(alpha: active ? 0.42 : 0.18),
          Colors.transparent,
        ],
      ).createShader(Rect.fromCircle(center: center, radius: size.shortestSide * 0.19));
    canvas.drawCircle(center, size.shortestSide * 0.19, centerGlow);

    final core = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: <Color>[AppColors.lime, Color(0xFFB8ED5D)],
      ).createShader(Rect.fromCircle(center: center, radius: size.shortestSide * 0.115));
    canvas.drawCircle(center, size.shortestSide * 0.115, core);

    final link = Paint()
      ..color = AppColors.ink
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.shortestSide * 0.018
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: size.shortestSide * 0.052),
      -math.pi * 0.12,
      math.pi * 0.7,
      false,
      link,
    );
    canvas.drawCircle(
      center + Offset(size.shortestSide * 0.018, -size.shortestSide * 0.012),
      size.shortestSide * 0.012,
      Paint()..color = AppColors.ink,
    );
  }

  @override
  bool shouldRepaint(covariant _OrbitPainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.active != active ||
      oldDelegate.deviceCount != deviceCount;
}

class ScanRadar extends StatefulWidget {
  const ScanRadar({super.key, this.size = 150, this.active = true});

  final double size;
  final bool active;

  @override
  State<ScanRadar> createState() => _ScanRadarState();
}

class _ScanRadarState extends State<ScanRadar> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 3),
  );

  @override
  void initState() {
    super.initState();
    if (widget.active) _controller.repeat();
  }

  @override
  void didUpdateWidget(covariant ScanRadar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active && !oldWidget.active) {
      _controller.repeat();
    } else if (!widget.active && oldWidget.active) {
      _controller.stop();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          return CustomPaint(
            painter: _RadarPainter(progress: _controller.value, active: widget.active),
          );
        },
      ),
    );
  }
}

class _RadarPainter extends CustomPainter {
  _RadarPainter({required this.progress, required this.active});

  final double progress;
  final bool active;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.shortestSide / 2 - 4;
    final ringPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = AppColors.ink.withValues(alpha: 0.1);
    for (var i = 1; i <= 3; i++) {
      canvas.drawCircle(center, radius * i / 3, ringPaint);
    }
    canvas.drawLine(
      Offset(center.dx - radius, center.dy),
      Offset(center.dx + radius, center.dy),
      ringPaint,
    );
    canvas.drawLine(
      Offset(center.dx, center.dy - radius),
      Offset(center.dx, center.dy + radius),
      ringPaint,
    );

    if (active) {
      final angle = progress * math.pi * 2 - math.pi / 2;
      final sweepRect = Rect.fromCircle(center: center, radius: radius);
      final sweepPaint = Paint()
        ..shader = SweepGradient(
          startAngle: angle - 0.8,
          endAngle: angle,
          colors: <Color>[
            AppColors.lime.withValues(alpha: 0),
            AppColors.lime.withValues(alpha: 0.38),
          ],
          transform: GradientRotation(angle - 0.8),
        ).createShader(sweepRect);
      canvas.drawCircle(center, radius, sweepPaint);

      final handPaint = Paint()
        ..color = AppColors.moss.withValues(alpha: 0.5)
        ..strokeWidth = 1.2;
      canvas.drawLine(
        center,
        Offset(
          center.dx + math.cos(angle) * radius,
          center.dy + math.sin(angle) * radius,
        ),
        handPaint,
      );

      for (var i = 0; i < 3; i++) {
        final dotAngle = i * 2.2 + 0.8;
        final dotRadius = radius * (0.34 + i * 0.17);
        final dot = Offset(
          center.dx + math.cos(dotAngle) * dotRadius,
          center.dy + math.sin(dotAngle) * dotRadius,
        );
        canvas.drawCircle(dot, 3.5, Paint()..color = AppColors.coral);
      }
    }

    canvas.drawCircle(
      center,
      5,
      Paint()..color = active ? AppColors.ink : AppColors.sage,
    );
  }

  @override
  bool shouldRepaint(covariant _RadarPainter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.active != active;
}

class DashedLine extends StatelessWidget {
  const DashedLine({super.key, this.color = AppColors.line, this.height = 1});

  final Color color;
  final double height;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      width: double.infinity,
      child: CustomPaint(
        painter: _DashedLinePainter(color: color, height: height),
      ),
    );
  }
}

class _DashedLinePainter extends CustomPainter {
  _DashedLinePainter({required this.color, required this.height});

  final Color color;
  final double height;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = height
      ..strokeCap = StrokeCap.round;
    const dash = 4.0;
    const gap = 5.0;
    var x = 0.0;
    while (x < size.width) {
      canvas.drawLine(Offset(x, height / 2), Offset(math.min(x + dash, size.width), height / 2), paint);
      x += dash + gap;
    }
  }

  @override
  bool shouldRepaint(covariant _DashedLinePainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.height != height;
}
