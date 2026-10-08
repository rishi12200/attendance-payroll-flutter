import 'package:app/core/api/app_exception.dart';
import 'package:app/features/attendance/data/attendance_views_providers.dart';
import 'package:app/features/attendance/domain/attendance_helpers.dart';
import 'package:app/features/attendance/domain/attendance_views.dart';
import 'package:app/features/attendance/presentation/admin_attendance_summary_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

String _currentMonth() =>
    istDateOf(DateTime.now().toUtc().toIso8601String()).substring(0, 7);

AttendanceSummary _summary({
  required int present,
  required int halfDays,
  required int absent,
  required double lop,
}) => AttendanceSummary(
  daysInMonth: 31,
  weeklyOffs: 4,
  holidays: 0,
  present: present,
  halfDays: halfDays,
  absent: absent,
  paidLeave: 0,
  unpaidLeave: 0,
  notJoinedOrLeftDays: 0,
  pending: 0,
  lop: lop,
  payableDays: 31 - lop,
);

Widget _app(
  String month,
  Future<List<AttendanceMonthSummaryRow>> Function()? load,
) => ProviderScope(
  overrides: [attendanceSummaryProvider(month).overrideWith((ref) => load!())],
  child: const MaterialApp(
    home: Scaffold(body: AdminAttendanceSummaryScreen()),
  ),
);

void main() {
  testWidgets('shows an empty state for a month without employee summaries', (
    tester,
  ) async {
    final month = _currentMonth();
    await tester.pumpWidget(_app(month, () async => []));
    await tester.pumpAndSettle();

    expect(find.text('No employee summaries for this month.'), findsOneWidget);
  });

  testWidgets('shows monthly totals per employee and opens that calendar', (
    tester,
  ) async {
    final month = _currentMonth();
    String? openedId;
    String? openedMonth;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          attendanceSummaryProvider(month).overrideWith(
            (ref) async => [
              AttendanceMonthSummaryRow(
                empId: 'employee-1',
                empCode: 'EMP001',
                name: 'Asha',
                summary: _summary(
                  present: 20,
                  halfDays: 1,
                  absent: 2,
                  lop: 2.5,
                ),
              ),
            ],
          ),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: AdminAttendanceSummaryScreen(
              onOpenEmployee: (id, selectedMonth) {
                openedId = id;
                openedMonth = selectedMonth;
              },
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Asha'), findsOneWidget);
    expect(
      find.text('EMP001 · Present 20 · Half days 1 · Absent 2'),
      findsOneWidget,
    );
    expect(find.text('LOP 2.5'), findsOneWidget);
    await tester.tap(
      find.byKey(const ValueKey('attendance-summary-employee-1')),
    );
    expect(openedId, 'employee-1');
    expect(openedMonth, month);
  });

  testWidgets('shows API error messages and retry control', (tester) async {
    final month = _currentMonth();
    await tester.pumpWidget(
      _app(
        month,
        () async => throw const AppException(
          code: 'SUMMARY_ERROR',
          message: 'Summary service unavailable.',
          details: {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Summary service unavailable.'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
  });
}
