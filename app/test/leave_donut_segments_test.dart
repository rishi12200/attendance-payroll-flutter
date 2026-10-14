import 'package:app/features/leave/domain/leave_donut_segments.dart';
import 'package:app/features/leave/domain/leave_type.dart';
import 'package:flutter_test/flutter_test.dart';

BalanceType _balance(String id, double? remaining) => BalanceType(
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
  test('includes only positive limited balances in response order', () {
    final result = computeDonutSegments([
      _balance('sick', 7.5),
      _balance('unlimited', null),
      _balance('empty', 0),
      _balance('negative', -1),
      _balance('casual', .5),
    ]);

    expect(result.segments.map((segment) => segment.leaveTypeId), [
      'sick',
      'casual',
    ]);
    expect(result.segments.map((segment) => segment.days), [7.5, .5]);
    expect(result.segments.map((segment) => segment.colorIndex), [0, 4]);
    expect(result.totalDays, 8);
    expect(result.hasLimitedTypes, isTrue);
    expect(result.hasUnlimitedTypes, isTrue);
  });

  test('starts at 12 o’clock and sweeps clockwise around a single segment', () {
    final result = computeDonutSegments([_balance('annual', 4)]);
    expect(result.segments.single.startAngle, -1.5707963267948966);
    expect(result.segments.single.sweepAngle, 6.283185307179586);
    expect(result.totalDays, 4);
  });

  test(
    'returns an empty zero-total result when every limited type is excluded',
    () {
      final result = computeDonutSegments([
        _balance('zero', 0),
        _balance('negative', -2),
      ]);
      expect(result.segments, isEmpty);
      expect(result.totalDays, 0);
      expect(result.hasLimitedTypes, isTrue);
      expect(result.hasUnlimitedTypes, isFalse);
    },
  );

  test('returns no chart eligibility for empty or unlimited-only types', () {
    final empty = computeDonutSegments([]);
    final unlimited = computeDonutSegments([_balance('unlimited', null)]);
    expect(empty.hasLimitedTypes, isFalse);
    expect(unlimited.hasLimitedTypes, isFalse);
    expect(unlimited.hasUnlimitedTypes, isTrue);
    expect(unlimited.segments, isEmpty);
  });

  test('uses half-day integer totals without decimal noise', () {
    final result = computeDonutSegments([
      _balance('half', .5),
      _balance('week', 7.5),
    ]);
    expect(result.totalDays, 8);
    expect(result.segments.map((segment) => segment.days), [.5, 7.5]);
    expect(
      result.segments.fold(0.0, (sum, segment) => sum + segment.sweepAngle),
      2 * 3.141592653589793,
    );
  });

  test('sweeps sum to exactly one circle for two and eight segments', () {
    for (final count in [2, 8]) {
      final result = computeDonutSegments([
        for (var index = 0; index < count; index++)
          _balance('type-$index', index + .5),
      ]);
      var sum = 0.0;
      for (final segment in result.segments) {
        sum += segment.sweepAngle;
      }
      expect(sum, 2 * 3.141592653589793);
    }
  });

  test('uses the 25 degree label threshold', () {
    final result = computeDonutSegments([
      _balance('small', 1),
      _balance('large', 20),
    ]);
    expect(showDonutSegmentLabel(result.segments.first), isFalse);

    final threshold = computeDonutSegments([
      _balance('at-threshold', 25),
      _balance('rest', 335),
    ]);
    expect(showDonutSegmentLabel(threshold.segments.first), isTrue);
  });
}
