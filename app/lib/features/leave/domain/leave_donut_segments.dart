import 'dart:math' as math;

import 'leave_type.dart';

const double _donutStartAngle = -math.pi / 2;
const double _fullCircle = math.pi * 2;
const double _zeroTolerance = 1e-9;

class DonutSegment {
  const DonutSegment({
    required this.leaveTypeId,
    required this.name,
    required this.days,
    required this.startAngle,
    required this.sweepAngle,
    required this.colorIndex,
  });

  final String leaveTypeId;
  final String name;
  final double days;
  final double startAngle;
  final double sweepAngle;
  final int colorIndex;
}

class DonutSegments {
  const DonutSegments({
    required this.segments,
    required this.totalDays,
    required this.hasLimitedTypes,
    required this.hasUnlimitedTypes,
  });

  final List<DonutSegment> segments;
  final double totalDays;
  final bool hasLimitedTypes;
  final bool hasUnlimitedTypes;
}

DonutSegments computeDonutSegments(List<BalanceType> types) {
  final positiveTypes = <({BalanceType type, int index, int halfDays})>[];
  var totalHalfDays = 0;
  var hasLimitedTypes = false;
  var hasUnlimitedTypes = false;

  for (var index = 0; index < types.length; index++) {
    final type = types[index];
    final remaining = type.remaining;
    if (remaining == null) {
      hasUnlimitedTypes = true;
      continue;
    }
    hasLimitedTypes = true;
    if (remaining <= _zeroTolerance) continue;

    final halfDays = (remaining * 2).round();
    if (halfDays <= 0) continue;
    positiveTypes.add((type: type, index: index, halfDays: halfDays));
    totalHalfDays += halfDays;
  }

  var assignedSweep = 0.0;
  final segments = <DonutSegment>[];
  for (var index = 0; index < positiveTypes.length; index++) {
    final item = positiveTypes[index];
    final sweepAngle = index == positiveTypes.length - 1
        ? _fullCircle - assignedSweep
        : item.halfDays / totalHalfDays * _fullCircle;
    segments.add(
      DonutSegment(
        leaveTypeId: item.type.leaveTypeId,
        name: item.type.name,
        days: item.halfDays / 2,
        startAngle: _donutStartAngle + assignedSweep,
        sweepAngle: sweepAngle,
        colorIndex: item.index,
      ),
    );
    assignedSweep += sweepAngle;
  }

  return DonutSegments(
    segments: List.unmodifiable(segments),
    totalDays: totalHalfDays / 2,
    hasLimitedTypes: hasLimitedTypes,
    hasUnlimitedTypes: hasUnlimitedTypes,
  );
}

bool showDonutSegmentLabel(DonutSegment segment) =>
    segment.sweepAngle >= 25 * math.pi / 180;
