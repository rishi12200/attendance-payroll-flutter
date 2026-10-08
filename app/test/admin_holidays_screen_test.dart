import 'package:app/core/api/app_exception.dart';
import 'package:app/features/attendance/data/attendance_views_providers.dart';
import 'package:app/features/attendance/data/attendance_views_repository.dart';
import 'package:app/features/attendance/domain/attendance_helpers.dart';
import 'package:app/features/attendance/domain/attendance_views.dart';
import 'package:app/features/attendance/presentation/admin_holidays_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeViewsRepository extends Fake implements AttendanceViewsRepository {
  List<AttendanceHoliday> holidays = const [];
  Object? createError;
  AttendanceHoliday? created;
  String? deletedDate;

  @override
  Future<AttendanceHoliday> createHoliday({
    required String date,
    required String name,
  }) async {
    if (createError case final error?) throw error;
    return created = AttendanceHoliday(date: date, name: name);
  }

  @override
  Future<void> deleteHoliday(String date) async {
    deletedDate = date;
  }
}

String _currentYear() =>
    istDateOf(DateTime.now().toUtc().toIso8601String()).substring(0, 4);

Widget _app(_FakeViewsRepository repository) {
  final year = _currentYear();
  return ProviderScope(
    overrides: [
      attendanceViewsRepositoryProvider.overrideWithValue(repository),
      attendanceHolidaysProvider(year)
          .overrideWith((ref) async => repository.holidays),
    ],
    child: const MaterialApp(home: AdminHolidaysScreen()),
  );
}

void main() {
  testWidgets('lists holidays in date order with weekday labels', (
    tester,
  ) async {
    final repository = _FakeViewsRepository()
      ..holidays = const [
        AttendanceHoliday(date: '2026-10-20', name: 'Later'),
        AttendanceHoliday(date: '2026-10-01', name: 'Earlier'),
      ];
    await tester.pumpWidget(_app(repository));
    await tester.pumpAndSettle();

    expect(find.text('Thu, 1 Oct 2026'), findsOneWidget);
    expect(find.text('Tue, 20 Oct 2026'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('Earlier')).dy,
      lessThan(tester.getTopLeft(find.text('Later')).dy),
    );
  });

  testWidgets('adds a holiday', (tester) async {
    final repository = _FakeViewsRepository();
    await tester.pumpWidget(_app(repository));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('add-holiday')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('holiday-name')),
      'Company day',
    );
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(repository.created?.name, 'Company day');
    expect(find.text('Holiday added.'), findsOneWidget);
  });

  testWidgets('confirms deletion before removing a holiday', (tester) async {
    final repository = _FakeViewsRepository()
      ..holidays = const [
        AttendanceHoliday(date: '2026-10-08', name: 'Company day'),
      ];
    await tester.pumpWidget(_app(repository));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('delete-holiday-2026-10-08')));
    await tester.pumpAndSettle();
    expect(find.text('Delete holiday?'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('confirm-delete-holiday')));
    await tester.pumpAndSettle();
    expect(repository.deletedDate, '2026-10-08');
  });

  testWidgets('shows the server conflict message for a duplicate holiday', (
    tester,
  ) async {
    final repository = _FakeViewsRepository()
      ..createError = const AppException(
        code: 'HOLIDAY_EXISTS',
        message: 'A holiday already exists for this date.',
        details: {},
        statusCode: 409,
      );
    await tester.pumpWidget(_app(repository));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('add-holiday')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('holiday-name')),
      'Duplicate',
    );
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(
      find.text('A holiday already exists for this date.'),
      findsOneWidget,
    );
    expect(find.text('Add holiday'), findsOneWidget);
  });
}
