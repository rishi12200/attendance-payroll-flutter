import 'package:app/features/attendance/domain/attendance_views.dart';
import 'package:app/features/attendance/presentation/attendance_calendar_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

AttendanceCalendar _calendar({
  String today = '2026-10-08',
  List<AttendanceCalendarDay>? days,
}) => AttendanceCalendar(
  month: '2026-10',
  today: today,
  serverTime: '${today}T12:00:00.000Z',
  summary: const AttendanceSummary(
    daysInMonth: 31,
    weeklyOffs: 4,
    holidays: 1,
    present: 1,
    halfDays: 1,
    absent: 2,
    paidLeave: 1,
    unpaidLeave: 1,
    notJoinedOrLeftDays: 0,
    pending: 24,
    lop: 3.5,
    payableDays: 27.5,
  ),
  days: days ?? _days(),
);

List<AttendanceCalendarDay> _days() {
  const statuses = [
    'P',
    'H',
    'A',
    'L',
    'UL',
    'WEEKLY_OFF',
    'HOLIDAY',
    'NOT_JOINED',
    'LEFT',
    'PENDING',
  ];
  return [
    for (var day = 1; day <= 31; day++)
      AttendanceCalendarDay(
        date: '2026-10-${day.toString().padLeft(2, '0')}',
        weekday: DateTime.utc(2026, 10, day).weekday % 7,
        status: day <= statuses.length ? statuses[day - 1] : 'PENDING',
        derived: day == 3,
        holidayName: day == 7 ? 'Founders day' : null,
        inTime: day == 1 ? '2026-10-01T03:30:00.000Z' : null,
        outTime: day == 1 ? '2026-10-01T11:30:00.000Z' : null,
        workedMinutes: day == 1 ? 480 : null,
        inBranchName: day == 1 ? 'Chennai Office' : null,
        source: day == 1 ? 'admin_edit' : null,
        editedBy: day == 1 ? 'admin-uid' : null,
        editedAt: day == 1 ? '2026-10-02T10:00:00.000Z' : null,
      ),
  ];
}

Widget _app({
  required AttendanceCalendar calendar,
  required String month,
  required ValueChanged<String> onMonthChanged,
  AttendanceCalendarEditCallback? onEdit,
}) => MaterialApp(
  home: Scaffold(
    body: SingleChildScrollView(
      child: AttendanceCalendarWidget(
        calendar: calendar,
        month: month,
        onMonthChanged: onMonthChanged,
        onEdit: onEdit,
      ),
    ),
  ),
);

void main() {
  testWidgets('shows status codes, status colors, legend and summary values', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(calendar: _calendar(), month: '2026-10', onMonthChanged: (_) {}),
    );

    const codes = {
      '2026-10-01': 'P',
      '2026-10-02': 'H',
      '2026-10-03': 'A',
      '2026-10-04': 'L',
      '2026-10-05': 'UL',
      '2026-10-06': 'WO',
      '2026-10-07': 'HOL',
      '2026-10-08': '-',
    };
    final colors = <Color>{};
    for (final entry in codes.entries) {
      final cell = find.byKey(ValueKey('calendar-status-${entry.key}'));
      expect(
        find.descendant(of: cell, matching: find.text(entry.value)),
        findsOneWidget,
      );
      final container = tester.widget<Container>(cell);
      final color = (container.decoration! as BoxDecoration).color;
      expect(color, isNotNull);
      colors.add(color!);
    }
    expect(colors.length, greaterThan(5));

    expect(find.text('Present: 1'), findsOneWidget);
    expect(find.text('Half days: 1'), findsOneWidget);
    expect(find.text('Absent: 2'), findsOneWidget);
    expect(find.text('Paid leave: 1'), findsOneWidget);
    expect(find.text('Unpaid leave: 1'), findsOneWidget);
    expect(find.text('LOP days: 3.5'), findsOneWidget);
    expect(find.text('Payable days: 27.5'), findsOneWidget);
    expect(find.text('Not joined / left / pending'), findsOneWidget);
    expect(find.text('Weekly off'), findsOneWidget);
  });

  testWidgets('day sheet describes the date, status, times and edit history', (
    tester,
  ) async {
    var editCalled = false;
    await tester.pumpWidget(
      _app(
        calendar: _calendar(),
        month: '2026-10',
        onMonthChanged: (_) {},
        onEdit: (_) async {
          editCalled = true;
        },
      ),
    );
    await tester.tap(find.byKey(const ValueKey('calendar-day-2026-10-01')));
    await tester.pumpAndSettle();

    expect(find.text('Thu, 1 Oct 2026'), findsOneWidget);
    expect(find.text('Status: Present (P)'), findsOneWidget);
    expect(find.text('In: 09:00 AM'), findsOneWidget);
    expect(find.text('Out: 05:00 PM'), findsOneWidget);
    expect(find.text('Worked: 8 h'), findsOneWidget);
    expect(find.text('In branch: Chennai Office'), findsOneWidget);
    expect(find.text('Source: Admin edit'), findsOneWidget);
    expect(find.text('Edited by: admin-uid'), findsOneWidget);
    expect(find.text('Edited at: Fri, 2 Oct 2026 03:30 PM'), findsOneWidget);
    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();
    expect(editCalled, isTrue);
  });

  testWidgets('explains derived absences and holiday names in the day sheet', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(calendar: _calendar(), month: '2026-10', onMonthChanged: (_) {}),
    );
    await tester.tap(find.byKey(const ValueKey('calendar-day-2026-10-03')));
    await tester.pumpAndSettle();
    expect(find.text('No attendance recorded'), findsOneWidget);
    Navigator.of(tester.element(find.byType(BottomSheet))).pop();
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('calendar-day-2026-10-07')));
    await tester.pumpAndSettle();
    expect(find.text('Holiday: Founders day'), findsOneWidget);
  });

  testWidgets('month arrows enforce server-current and 12-month limits', (
    tester,
  ) async {
    var changed = '';
    await tester.pumpWidget(
      _app(
        calendar: _calendar(),
        month: '2026-10',
        onMonthChanged: (month) => changed = month,
      ),
    );
    expect(
      tester
          .widget<IconButton>(find.byKey(const ValueKey('next-month')))
          .onPressed,
      isNull,
    );
    await tester.tap(find.byKey(const ValueKey('previous-month')));
    expect(changed, '2026-09');

    await tester.pumpWidget(
      _app(
        calendar: _calendar(),
        month: '2025-10',
        onMonthChanged: (month) => changed = month,
      ),
    );
    expect(
      tester
          .widget<IconButton>(find.byKey(const ValueKey('previous-month')))
          .onPressed,
      isNull,
    );
    expect(
      tester
          .widget<IconButton>(find.byKey(const ValueKey('next-month')))
          .onPressed,
      isNotNull,
    );
  });
}
