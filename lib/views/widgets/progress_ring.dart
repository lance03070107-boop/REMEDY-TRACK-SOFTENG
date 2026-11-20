import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../core/theme/design_tokens.dart';
import '../../core/theme/status_colors.dart';

/// Smooth animated circular progress ring for daily dose adherence.
/// Displays clear percentage and ratio (e.g. "3 of 4") in high-contrast typography.
class ProgressRing extends StatefulWidget {
  final double progress; // 0.0 to 1.0
  final int takenCount;
  final int totalCount;
  final double size;
  final double strokeWidth;
  final Color? activeColor;

  const ProgressRing({
    super.key,
    required this.progress,
    required this.takenCount,
    required this.totalCount,
    this.size = 120.0,
    this.strokeWidth = 10.0,
    this.activeColor,
  });

  @override
  State<ProgressRing> createState() => _ProgressRingState();
}

class _ProgressRingState extends State<ProgressRing>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _animation = Tween<double>(begin: 0.0, end: widget.progress.clamp(0.0, 1.0))
        .animate(CurvedAnimation(
      parent: _controller,
      curve: DesignTokens.curveSpring,
    ));
    _controller.forward();
  }

  @override
  void didUpdateWidget(ProgressRing oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.progress != widget.progress) {
      _animation = Tween<double>(
        begin: _animation.value,
        end: widget.progress.clamp(0.0, 1.0),
      ).animate(CurvedAnimation(
        parent: _controller,
        curve: DesignTokens.curveSpring,
      ));
      _controller.forward(from: 0.0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final statusColors = theme.extension<StatusColors>() ??
        (theme.brightness == Brightness.dark
            ? StatusColors.dark
            : StatusColors.light);

    final progressColor = widget.activeColor ??
        (widget.progress >= 1.0
            ? statusColors.taken
            : theme.colorScheme.primary);

    final trackColor =
        theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5);

    return Semantics(
      label:
          'Daily on-time rate: ${(widget.progress.clamp(0.0, 1.0) * 100).round()} percent, ${widget.takenCount} of ${widget.totalCount} doses taken',
      child: SizedBox(
        width: widget.size,
        height: widget.size,
        child: AnimatedBuilder(
          animation: _animation,
          builder: (context, child) {
            final currentVal = _animation.value;
            final pctInt = (currentVal * 100).round();

            return Stack(
              alignment: Alignment.center,
              children: [
                CustomPaint(
                  size: Size(widget.size, widget.size),
                  painter: _RingPainter(
                    progress: currentVal,
                    strokeWidth: widget.strokeWidth,
                    trackColor: trackColor,
                    progressColor: progressColor,
                  ),
                ),
                Padding(
                  padding: EdgeInsets.all(widget.strokeWidth + 4),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '$pctInt%',
                          style: theme.textTheme.headlineMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                            letterSpacing: -1.0,
                            color: theme.colorScheme.onSurface,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${widget.takenCount} of ${widget.totalCount}',
                          style: theme.textTheme.labelSmall?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  final double progress;
  final double strokeWidth;
  final Color trackColor;
  final Color progressColor;

  _RingPainter({
    required this.progress,
    required this.strokeWidth,
    required this.trackColor,
    required this.progressColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width - strokeWidth) / 2;

    // Background track
    final trackPaint = Paint()
      ..color = trackColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    canvas.drawCircle(center, radius, trackPaint);

    if (progress <= 0) return;

    // Progress arc
    final progressPaint = Paint()
      ..color = progressColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    final sweepAngle = 2 * math.pi * progress;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi / 2, // Start at 12 o'clock
      sweepAngle,
      false,
      progressPaint,
    );
  }

  @override
  bool shouldRepaint(_RingPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.trackColor != trackColor ||
        oldDelegate.progressColor != progressColor;
  }
}
