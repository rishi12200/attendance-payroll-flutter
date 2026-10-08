import 'package:app/core/api/app_exception.dart';
import 'package:app/features/attendance/data/attendance_views_providers.dart';
import 'package:app/features/attendance/data/attendance_views_repository.dart';
import 'package:app/features/attendance/domain/attendance_edit_validation.dart';
import 'package:app/features/attendance/domain/attendance_views.dart';
import 'package:app/features/attendance/presentation/admin_attendance_edit_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeViewsRepository extends Fake implements AttendanceViewsRepository {
  String? status;
  String? inTime;
  String? outTime;
  String? reason;
  Object? error;

  @override
  Future<AttendanceCalendarDay> editAttendance({
    required String empId,
    required String date,
    required String status,
    required String reason,
    String? inTime,
    String? outTime,
  }) async {
    this.status = status;
    this.inTime = inTime;
    this.outTime = outTime;
    this.reason = reason;
    if (error case final value?) throw value;
    return AttendanceCalendarDay(
      date: date,
      weekday: 4,
      status: status,
      derived: false,
      inTime: inTime,
      outTime: outTime,
    );
  }
}

const _day = AttendanceCalendarDay(
  date: '2026-10-08',
  weekday: 4,
  status: 'P',
  derived: false,
  inTime: '2026-10-08T03:30:00.000Z',
  outTime: '2026-10-08T11:30:00.000Z',
  workedMinutes: 480,
);

Widget _app(_FakeViewsRepository repository, {VoidCallback? onSaved}) =>
    ProviderScope(
      overrides: [
        attendanceViewsRepositoryProvider.overrideWithValue(repository),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: const Text('Calendar'),
          floatingActionButton: Builder(
            builder: (context) => FloatingActionButton(
              onPressed: () => showAdminAttendanceEditSheet(
                context: context,
                empId: 'employee-1',
                serverToday: '2026-10-08',
                day: _day,
                onSaved: onSaved ?? () {},
              ),
              child: const Icon(Icons.edit),
            ),
          ),
        ),
      ),
    );

void main() {
  test("validates the server's reason and time rules", () {
    final inTime = DateTime.utc(2026, 10, 8, 3, 30);
    expect(
      validateAttendanceEdit(
        status: 'P',
        inTime: inTime,
        outTime: null,
        reason: ' ',
      ),
      'Enter a reason for this edit.',
    );
    expect(
      validateAttendanceEdit(
        status: 'A',
        inTime: inTime,
        outTime: null,
        reason: 'Correction',
      ),
      'Times are only allowed with Present or Half day.',
    );
    expect(
      validateAttendanceEdit(
        status: 'P',
        inTime: inTime,
        outTime: DateTime.utc(2026, 10, 8, 3, 29),
        reason: 'Correction',
      ),
      'Out time must be after in time.',
    );
    expect(
      validateAttendanceEdit(
        status: 'P',
        inTime: inTime,
        outTime: DateTime.utc(2026, 10, 9, 4, 0),
        reason: 'Correction',
      ),
      'Out time must be within 24 hours of in time.',
    );
    expect(
      validateAttendanceEdit(
        status: 'P',
        inTime: inTime,
        outTime: DateTime.utc(2026, 10, 8, 11, 30),
        reason: 'Correction',
      ),
      isNull,
    );
  });

  testWidgets('requires a reason and submits selected values to the API', (
    tester,
  ) async {
    final repository = _FakeViewsRepository();
    var saved = false;
    await tester.pumpWidget(_app(repository, onSaved: () => saved = true));
    await tester.tap(find.byIcon(Icons.edit));
    await tester.pumpAndSettle();

    expect(find.text('In time: 09:00 AM'), findsOneWidget);
    expect(find.text('Out time: 05:00 PM'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('save-attendance-edit')));
    await tester.pumpAndSettle();
    expect(find.text('Enter a reason for this edit.'), findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey('attendance-edit-reason')),
      'Corrected punch times',
    );
    expect(
      tester
          .widget<TextField>(
            find.byKey(const ValueKey('attendance-edit-reason')),
          )
          .maxLength,
      200,
    );
    await tester.tap(find.byKey(const ValueKey('save-attendance-edit')));
    await tester.pumpAndSettle();

    expect(repository.status, 'P');
    expect(repository.inTime, '2026-10-08T03:30:00.000Z');
    expect(repository.outTime, '2026-10-08T11:30:00.000Z');
    expect(repository.reason, 'Corrected punch times');
    expect(saved, isTrue);
    expect(find.text('Edit attendance · 2026-10-08'), findsNothing);
  });

  testWidgets('disables time pickers for leave and absent statuses', (
    tester,
  ) async {
    await tester.pumpWidget(_app(_FakeViewsRepository()));
    await tester.tap(find.byIcon(Icons.edit));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('attendance-edit-status')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Absent').last);
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<OutlinedButton>(find.byKey(const ValueKey('pick-in-time')))
          .onPressed,
      isNull,
    );
    expect(
      tester
          .widget<OutlinedButton>(find.byKey(const ValueKey('pick-out-time')))
          .onPressed,
      isNull,
    );
  });

  testWidgets('shows server errors without closing the editor', (tester) async {
    final repository = _FakeViewsRepository()
      ..error = const AppException(
        code: 'MONTH_LOCKED',
        message: 'This month is locked.',
        details: {},
      );
    await tester.pumpWidget(_app(repository));
    await tester.tap(find.byIcon(Icons.edit));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('attendance-edit-reason')),
      'Correction',
    );
    await tester.tap(find.byKey(const ValueKey('save-attendance-edit')));
    await tester.pumpAndSettle();

    expect(find.text('This month is locked.'), findsOneWidget);
    expect(find.text('Edit attendance · 2026-10-08'), findsOneWidget);
  });
}
