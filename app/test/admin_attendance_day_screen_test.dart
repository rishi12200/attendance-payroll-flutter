import 'dart:async';

import 'package:app/core/api/app_exception.dart';
import 'package:app/features/attendance/data/attendance_views_providers.dart';
import 'package:app/features/attendance/domain/attendance_helpers.dart';
import 'package:app/features/attendance/domain/attendance_views.dart';
import 'package:app/features/attendance/presentation/admin_attendance_day_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

String _today() =>
    istDateOf(DateTime.now().toUtc().toIso8601String());

AttendanceByDate _response({
  required String date,
  required String today,
  List<AttendanceDateRow> rows = const [],
  Map<String, int> totals = const {},
}) => AttendanceByDate(date: date, today: today, rows: rows, totals: totals);

AttendanceDateRow _row({
  required String id,
  bool noCheckout = false,
  bool checkedInNow = false,
}) => AttendanceDateRow(
  empId: id,
  empCode: 'EMP001',
  name: 'Asha',
  designation: 'Associate',
  status: 'P',
  derived: false,
  noCheckout: noCheckout,
  checkedInNow: checkedInNow,
  inTime: '2026-10-08T03:30:00.000Z',
  outTime: noCheckout || checkedInNow
      ? null
      : '2026-10-08T11:30:00.000Z',
  workedMinutes: noCheckout || checkedInNow ? null : 480,
  inBranchName: 'Chennai Office',
);

Widget _app(
  String date,
  Future<AttendanceByDate> Function()? load, {
  Completer<AttendanceByDate>? completer,
  OpenEmployeeAttendance? onOpenEmployee,
}) => ProviderScope(
  overrides: [
    attendanceByDateProvider(date).overrideWith((ref) {
      if (completer != null) return completer.future;
      return load!();
    }),
  ],
  child: MaterialApp(
    home: Scaffold(
      body: AdminAttendanceDayScreen(onOpenEmployee: onOpenEmployee),
    ),
  ),
);

void main() {
  testWidgets('shows loading state while the day request is pending', (
    tester,
  ) async {
    final date = _today();
    final completer = Completer<AttendanceByDate>();
    await tester.pumpWidget(_app(date, null, completer: completer));
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('shows the empty state for a day with no employees', (
    tester,
  ) async {
    final date = _today();
    await tester.pumpWidget(
      _app(date, () async => _response(date: date, today: date)),
    );
    await tester.pumpAndSettle();

    expect(find.text('No employees scheduled for this date.'), findsOneWidget);
    expect(find.text('Present: 0'), findsOneWidget);
  });

  testWidgets('shows server errors and a retry action', (tester) async {
    final date = _today();
    await tester.pumpWidget(
      _app(
        date,
        () async => throw const AppException(
          code: 'TEST_ERROR',
          message: 'The day view is unavailable.',
          details: {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('The day view is unavailable.'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
  });

  testWidgets('shows rows, punch markers and opens an employee calendar', (
    tester,
  ) async {
    final date = _today();
    String? openedEmployee;
    String? openedMonth;
    await tester.pumpWidget(
      _app(
        date,
        () async => _response(
          date: date,
          today: date,
          rows: [
            _row(id: 'past-open', noCheckout: true),
            _row(id: 'today-open', checkedInNow: true),
          ],
          totals: {'P': 2},
        ),
        onOpenEmployee: (empId, month) {
          openedEmployee = empId;
          openedMonth = month;
        },
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('No check-out'), findsOneWidget);
    expect(find.text('Checked in now'), findsOneWidget);
    expect(find.text('In: 09:00 AM'), findsNWidgets(2));
    expect(find.text('In branch: Chennai Office'), findsNWidgets(2));
    await tester.tap(find.byKey(const ValueKey('attendance-row-past-open')));
    expect(openedEmployee, 'past-open');
    expect(openedMonth, date.substring(0, 7));
  });
}
