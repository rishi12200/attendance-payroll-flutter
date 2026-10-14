import 'package:flutter/material.dart';

import '../domain/leave_type.dart';
import '../domain/remaining_leave_slices.dart';
import 'remaining_leave_palette.dart';
import 'remaining_leave_pie_painter.dart';

class RemainingLeaveChartCard extends StatelessWidget {
  const RemainingLeaveChartCard({
    required this.balance,
    required this.sliceData,
    super.key,
  });

  final LeaveBalance balance;
  final RemainingLeaveSlices sliceData;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Remaining leave days',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            Text(balance.label, style: Theme.of(context).textTheme.bodySmall),
            if (sliceData.slices.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 28),
                child: Center(child: Text('No remaining leave days to show.')),
              )
            else ...[
              const SizedBox(height: 12),
              Center(
                child: Semantics(
                  label: _semanticsLabel(),
                  child: ExcludeSemantics(
                    child: SizedBox.square(
                      dimension: 200,
                      child: CustomPaint(
                        key: const ValueKey('remaining-leave-pie'),
                        painter: RemainingLeavePiePainter(
                          slices: sliceData.slices,
                          gapColor: scheme.surface,
                          colorScheme: scheme,
                          textStyle: Theme.of(context).textTheme.labelMedium!,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              LayoutBuilder(
                builder: (context, constraints) => Wrap(
                  spacing: 12,
                  runSpacing: 8,
                  children: [
                    for (final slice in sliceData.slices)
                      SizedBox(
                        width: constraints.maxWidth,
                        child: Row(
                          children: [
                            Container(
                              width: 12,
                              height: 12,
                              decoration: BoxDecoration(
                                color: remainingLeaveColor(
                                  slice.colorIndex,
                                  scheme,
                                ),
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(child: Text(slice.name)),
                            const SizedBox(width: 8),
                            Text(pluralDays(slice.days)),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 8),
            Text(
              'Days left after pending requests.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            if (sliceData.noLimit.isNotEmpty || sliceData.zeroLeft.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  _excludedNote(),
                  style: Theme.of(context).textTheme.bodySmall
                      ?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ),
          ],
        ),
      ),
    );
  }

  String _semanticsLabel() =>
      'Remaining leave days for ${balance.label}: ${sliceData.slices.map((slice) => '${slice.name}, ${pluralDays(slice.days)}').join('; ')}';

  String _excludedNote() {
    final excluded = [
      ...sliceData.noLimit.map((name) => '$name (no limit)'),
      ...sliceData.zeroLeft.map((name) => '$name (0 left)'),
    ];
    return 'Not in the chart: ${excluded.join(', ')}';
  }
}
