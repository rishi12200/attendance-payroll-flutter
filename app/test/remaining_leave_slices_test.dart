import 'package:flutter_test/flutter_test.dart';
import 'package:app/features/leave/domain/leave_type.dart';
import 'package:app/features/leave/domain/remaining_leave_slices.dart';

BalanceType balance(String id, double? remaining) => BalanceType(
  leaveTypeId: id,
  name: id,
  code: id.toUpperCase(),
  paid: true,
  allowHalfDay: true,
  quota: 10,
  used: 0,
  pending: 0,
  remaining: remaining,
);

void main() {
  test(
    'preserves balance order, original palette indices, and decimal days',
    () {
      final result = buildRemainingSlices(
        balanceTypes: [balance('a', 1.5), balance('b', 0), balance('c', 2.25)],
      );
      expect(result.slices.map((slice) => slice.leaveTypeId), ['a', 'c']);
      expect(result.slices.map((slice) => slice.colorIndex), [0, 2]);
      expect(result.slices.map((slice) => slice.days), [1.5, 2.25]);
      expect(result.zeroLeft, ['b']);
    },
  );

  test('filters by active types and reports unlimited and zero names', () {
    final result = buildRemainingSlices(
      balanceTypes: [
        balance('unlimited', null),
        balance('zero', 0),
        balance('negative', -1),
        balance('positive', .5),
      ],
      activeTypeIds: {'unlimited', 'zero', 'positive'},
    );
    expect(result.slices.single.days, .5);
    expect(result.slices.single.colorIndex, 3);
    expect(result.noLimit, ['unlimited']);
    expect(result.zeroLeft, ['zero']);
  });

  test('keeps all positive types when active type IDs are unavailable', () {
    final result = buildRemainingSlices(
      balanceTypes: [balance('a', 7.5), balance('b', .5)],
      activeTypeIds: null,
    );
    expect(result.slices.map((slice) => slice.leaveTypeId), ['a', 'b']);
    expect(result.slices.map((slice) => slice.days), [7.5, .5]);
  });

  test('uses exact final remainder for a full circle and label threshold', () {
    final below = buildRemainingSlices(
      balanceTypes: [balance('small', 1), balance('large', 20)],
    );
    expect(
      below.slices.fold(0.0, (sum, slice) => sum + slice.sweepRadians),
      6.283185307179586,
    );
    expect(showRemainingSliceLabel(below.slices.first), isFalse);
    expect(showRemainingSliceLabel(below.slices.last), isTrue);

    final atThreshold = buildRemainingSlices(
      balanceTypes: [balance('quarter-ish', 25), balance('rest', 335)],
    );
    expect(showRemainingSliceLabel(atThreshold.slices.first), isTrue);
  });

  test('sweeps sum to one full circle for one, two, and eight slices', () {
    for (final count in [1, 2, 8]) {
      final result = buildRemainingSlices(
        balanceTypes: [
          for (var index = 0; index < count; index++)
            balance('type-$index', index + 0.5),
        ],
      );
      var sum = 0.0;
      for (final slice in result.slices) {
        sum += slice.sweepRadians;
      }
      expect(sum, 2 * 3.141592653589793);
    }
  });

  test('empty balances have no slices or exclusion names', () {
    final result = buildRemainingSlices(balanceTypes: []);
    expect(result.slices, isEmpty);
    expect(result.noLimit, isEmpty);
    expect(result.zeroLeft, isEmpty);
  });
}
