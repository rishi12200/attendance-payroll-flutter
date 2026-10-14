import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../domain/leave_donut_segments.dart';
import '../domain/leave_type.dart';
import 'remaining_leave_donut_painter.dart';
import 'remaining_leave_palette.dart';

class RemainingLeaveDonut extends StatelessWidget {
  const RemainingLeaveDonut({required this.balance, super.key});

  final LeaveBalance balance;

  @override
  Widget build(BuildContext context) {
    final calculation = computeDonutSegments(balance.types);
    if (!calculation.hasLimitedTypes) return const SizedBox.shrink();

    final hasRemainingDays = calculation.segments.isNotEmpty;
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final diameter = math.min(180.0, constraints.maxWidth);
            final centerDiameter =
                diameter - RemainingLeaveDonutPainter.ringThickness * 2;
            return Column(
              children: [
                Semantics(
                  label: _semanticsLabel(calculation),
                  child: ExcludeSemantics(
                    child: SizedBox.square(
                      dimension: diameter,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          CustomPaint(
                            key: const ValueKey('remaining-leave-donut'),
                            size: Size.square(diameter),
                            painter: RemainingLeaveDonutPainter(
                              segments: calculation.segments,
                              gapColor: scheme.surface,
                              textStyle: Theme.of(context)
                                  .textTheme
                                  .labelMedium!,
                              hasRemainingDays: hasRemainingDays,
                            ),
                          ),
                          SizedBox(
                            width: centerDiameter,
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                FittedBox(
                                  fit: BoxFit.scaleDown,
                                  child: Text(
                                    formatDays(calculation.totalDays),
                                    style: Theme.of(context)
                                        .textTheme
                                        .headlineMedium,
                                  ),
                                ),
                                FittedBox(
                                  fit: BoxFit.scaleDown,
                                  child: Text(
                                    'days left',
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodySmall,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                if (!hasRemainingDays)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      'No leave days remaining.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                if (calculation.segments.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  for (final segment in calculation.segments)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 3),
                      child: Row(
                        children: [
                          Container(
                            width: 12,
                            height: 12,
                            decoration: BoxDecoration(
                              color: remainingLeaveColor(segment.colorIndex),
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(child: Text(segment.name)),
                          const SizedBox(width: 8),
                          Text(pluralDays(segment.days)),
                        ],
                      ),
                    ),
                ],
                if (calculation.hasUnlimitedTypes)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      'Types with no limit are not shown in this chart.',
                      style: Theme.of(context).textTheme.bodySmall
                          ?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }

  String _semanticsLabel(DonutSegments calculation) {
    final entries = calculation.segments
        .map((segment) => '${segment.name} ${pluralDays(segment.days)}')
        .join(', ');
    if (entries.isEmpty) {
      return 'Remaining leave: no leave days remaining. Total 0 days left.';
    }
    return 'Remaining leave: $entries. Total ${pluralDays(calculation.totalDays)} left.';
  }
}
