import 'package:app/features/attendance/data/attendance_views_providers.dart';
import 'package:app/features/attendance/domain/attendance_helpers.dart';
import 'package:app/features/attendance/domain/attendance_month.dart';
import 'package:app/features/attendance/domain/attendance_views.dart';
import 'package:app/features/attendance/presentation/employee_attendance_calendar_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

AttendanceCalendar _calendar(String month) {
  final count = DateTime.utc(
    int.parse(month.substring(0, 4)),
    int.parse(month.substring(5, 7)) + 1,
    0,
  ).day;
  return AttendanceCalendar(
    month: month,
    today: '$month-08',
    serverTime: '$month-08T07:00:00.000Z',
    summary: AttendanceSummary(
      daysInMonth: count,
      weeklyOffs: 4,
      holidays: 0,
      present: 1,
      halfDays: 0,
      absent: 0,
      paidLeave: 0,
      unpaidLeave: 0,
      notJoinedOrLeftDays: 0,
      pending: count - 5,
      lop: 0,
      payableDays: count.toDouble(),
    ),
    days: [
      for (var day = 1; day <= count; day++)
        AttendanceCalendarDay(
          date: '$month-${day.toString().padLeft(2, '0')}',
          weekday:
              DateTime.utc(
                int.parse(month.substring(0, 4)),
                int.parse(month.substring(5, 7)),
                day,
              ).weekday %
              7,
          status: day == 8 ? 'P' : 'PENDING',
          derived: false,
        ),
    ],
  );
}

void main() {
  testWidgets('shows the signed-in employee calendar from the server', (
    tester,
  ) async {
    final firstMonth = istDateOf(DateTime.now().toUtc().toIso8601String())
        .substring(0, 7);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          myAttendanceCalendarProvider(firstMonth)
              .overrideWith((ref) async => _calendar(firstMonth)),
        ],
        child: const MaterialApp(home: EmployeeAttendanceCalendarScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Attendance'), findsOneWidget);
    expect(find.text(monthLabel(firstMonth)), findsOneWidget);
    expect(find.text('Present: 1'), findsOneWidget);
    expect(find.byKey(ValueKey('calendar-day-$firstMonth-08')), findsOneWidget);
  });
}
