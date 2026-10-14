import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../domain/leave_type.dart';
import '../domain/remaining_leave_slices.dart';
import 'remaining_leave_palette.dart';

class RemainingLeavePiePainter extends CustomPainter {
  const RemainingLeavePiePainter({
    required this.slices,
    required this.gapColor,
    required this.colorScheme,
    required this.textStyle,
  });

  final List<RemainingLeaveSlice> slices;
  final Color gapColor;
  final ColorScheme colorScheme;
  final TextStyle textStyle;

  List<String> get labelValues => [
    for (final slice in slices)
      if (showRemainingSliceLabel(slice)) formatDays(slice.days),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    if (slices.isEmpty) return;
    final center = size.center(Offset.zero);
    final radius = math.min(size.width, size.height) / 2;
    final rect = Rect.fromCircle(center: center, radius: radius);
    canvas.drawCircle(center, radius, Paint()..color = gapColor);
    final single = slices.length == 1;
    var start = -math.pi / 2;
    for (final slice in slices) {
      final gap = single ? 0.0 : math.min(.025, slice.sweepRadians / 4);
      final visibleSweep = slice.sweepRadians - gap;
      final paint = Paint()
        ..color = remainingLeaveColor(slice.colorIndex, colorScheme)
        ..style = PaintingStyle.fill;
      canvas.drawArc(rect, start + gap / 2, visibleSweep, true, paint);
      if (showRemainingSliceLabel(slice)) {
        final mid = start + slice.sweepRadians / 2;
        final labelCenter =
            center + Offset(math.cos(mid), math.sin(mid)) * radius * .59;
        final color = remainingLeaveColor(slice.colorIndex, colorScheme);
        final label = TextPainter(
          text: TextSpan(
            text: formatDays(slice.days),
            style: textStyle.copyWith(
              color: color.computeLuminance() > .45
                  ? Colors.black
                  : Colors.white,
              fontWeight: FontWeight.bold,
            ),
          ),
          textDirection: TextDirection.ltr,
          maxLines: 1,
        )..layout(maxWidth: radius * .8);
        label.paint(
          canvas,
          labelCenter - Offset(label.width / 2, label.height / 2),
        );
      }
      start += slice.sweepRadians;
    }
  }

  @override
  bool shouldRepaint(covariant RemainingLeavePiePainter oldDelegate) =>
      oldDelegate.slices != slices ||
      oldDelegate.gapColor != gapColor ||
      oldDelegate.colorScheme != colorScheme ||
      oldDelegate.textStyle != textStyle;
}
