import 'package:app/features/attendance/domain/attendance_month.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('handles month lengths, leap years and Monday-first grid offsets', () {
    expect(daysInMonth('2028-02'), 29);
    expect(daysInMonth('2026-02'), 28);
    expect(daysInMonth('2026-04'), 30);
    expect(daysInMonth('2026-10'), 31);
    expect(mondayFirstWeekdayOffset('2026-10'), 3);
    expect(mondayFirstWeekdayOffset('2028-02'), 1);
  });

  test('navigates month and year boundaries with readable labels', () {
    expect(previousMonth('2026-01'), '2025-12');
    expect(nextMonth('2026-12'), '2027-01');
    expect(monthLabel('2026-10'), 'October 2026');
  });

  test('limits navigation to the current month and 12 months back', () {
    final selected = AttendanceMonth.parse('2026-10');
    final current = AttendanceMonth.parse('2026-10');
    expect(
      selected.canNavigateTo(AttendanceMonth.parse('2026-10'), today: current),
      isTrue,
    );
    expect(
      selected.canNavigateTo(AttendanceMonth.parse('2027-01'), today: current),
      isFalse,
    );
    expect(
      selected.canNavigateTo(AttendanceMonth.parse('2025-10'), today: current),
      isTrue,
    );
    expect(
      selected.canNavigateTo(AttendanceMonth.parse('2025-09'), today: current),
      isFalse,
    );
  });

  test('rejects malformed or out-of-range month values', () {
    expect(() => AttendanceMonth.parse('2026-13'), throwsFormatException);
    expect(() => AttendanceMonth.parse('2026-1'), throwsFormatException);
  });
}
