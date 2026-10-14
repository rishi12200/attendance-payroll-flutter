import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../domain/leave_donut_segments.dart';
import '../domain/leave_type.dart';
import 'remaining_leave_palette.dart';

class RemainingLeaveDonutPainter extends CustomPainter {
  const RemainingLeaveDonutPainter({
    required this.segments,
    required this.gapColor,
    required this.textStyle,
    required this.hasRemainingDays,
  });

  static const ringThickness = 28.0;

  final List<DonutSegment> segments;
  final Color gapColor;
  final TextStyle textStyle;
  final bool hasRemainingDays;

  List<String> get labelValues => [
    for (final segment in segments)
      if (showDonutSegmentLabel(segment)) formatDays(segment.days),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = math.min(size.width, size.height) / 2;
    final rect = Rect.fromCircle(center: center, radius: radius);
    final ringPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = ringThickness
      ..strokeCap = StrokeCap.butt;

    if (!hasRemainingDays) {
      ringPaint.color = Colors.grey;
      canvas.drawCircle(center, radius - ringThickness / 2, ringPaint);
      return;
    }

    ringPaint.color = gapColor;
    canvas.drawCircle(center, radius - ringThickness / 2, ringPaint);
    final singleSegment = segments.length == 1;
    for (final segment in segments) {
      final gap = singleSegment
          ? 0.0
          : math.min(2 * math.pi / 180, segment.sweepAngle / 4);
      final visibleSweep = segment.sweepAngle - gap;
      ringPaint.color = remainingLeaveColor(segment.colorIndex);
      canvas.drawArc(
        rect.deflate(ringThickness / 2),
        segment.startAngle + gap / 2,
        visibleSweep,
        false,
        ringPaint,
      );
      if (showDonutSegmentLabel(segment)) {
        final middleAngle = segment.startAngle + segment.sweepAngle / 2;
        final textCenter =
            center +
            Offset(math.cos(middleAngle), math.sin(middleAngle)) *
                (radius - ringThickness / 2);
        final color = remainingLeaveColor(segment.colorIndex);
        final label = TextPainter(
          text: TextSpan(
            text: formatDays(segment.days),
            style: textStyle.copyWith(
              color: color.computeLuminance() > .45
                  ? Colors.black
                  : Colors.white,
              fontWeight: FontWeight.bold,
            ),
          ),
          textDirection: TextDirection.ltr,
          maxLines: 1,
        )..layout(maxWidth: ringThickness * 2.4);
        label.paint(
          canvas,
          textCenter - Offset(label.width / 2, label.height / 2),
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant RemainingLeaveDonutPainter oldDelegate) =>
      oldDelegate.segments != segments ||
      oldDelegate.gapColor != gapColor ||
      oldDelegate.textStyle != textStyle ||
      oldDelegate.hasRemainingDays != hasRemainingDays;
}
