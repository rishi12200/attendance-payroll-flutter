import 'dart:math' as math;

import 'leave_type.dart';

class RemainingLeaveSlice {
  const RemainingLeaveSlice({
    required this.leaveTypeId,
    required this.name,
    required this.code,
    required this.days,
    required this.colorIndex,
    required this.sweepRadians,
  });

  final String leaveTypeId;
  final String name;
  final String code;
  final double days;
  final int colorIndex;
  final double sweepRadians;
}

class RemainingLeaveSlices {
  const RemainingLeaveSlices({
    required this.slices,
    required this.noLimit,
    required this.zeroLeft,
  });

  final List<RemainingLeaveSlice> slices;
  final List<String> noLimit;
  final List<String> zeroLeft;
}

RemainingLeaveSlices buildRemainingSlices({
  required List<BalanceType> balanceTypes,
  Set<String>? activeTypeIds,
}) {
  final included = <({BalanceType type, int index})>[];
  final noLimit = <String>[];
  final zeroLeft = <String>[];
  for (var index = 0; index < balanceTypes.length; index++) {
    final type = balanceTypes[index];
    if (activeTypeIds != null && !activeTypeIds.contains(type.leaveTypeId)) {
      continue;
    }
    final remaining = type.remaining;
    if (remaining == null) {
      noLimit.add(type.name);
    } else if (remaining == 0) {
      zeroLeft.add(type.name);
    } else if (remaining > 0) {
      included.add((type: type, index: index));
    }
  }

  final total = included.fold<double>(
    0,
    (sum, item) => sum + item.type.remaining!,
  );
  var assigned = 0.0;
  final slices = <RemainingLeaveSlice>[];
  for (var index = 0; index < included.length; index++) {
    final item = included[index];
    final days = item.type.remaining!;
    final sweep = index == included.length - 1
        ? math.pi * 2 - assigned
        : (days / total) * math.pi * 2;
    slices.add(
      RemainingLeaveSlice(
        leaveTypeId: item.type.leaveTypeId,
        name: item.type.name,
        code: item.type.code,
        days: days,
        colorIndex: item.index,
        sweepRadians: sweep,
      ),
    );
    assigned += sweep;
  }
  return RemainingLeaveSlices(
    slices: List.unmodifiable(slices),
    noLimit: List.unmodifiable(noLimit),
    zeroLeft: List.unmodifiable(zeroLeft),
  );
}

bool showRemainingSliceLabel(RemainingLeaveSlice slice) =>
    slice.sweepRadians >= 25 * math.pi / 180;
