import 'package:app/core/api/app_exception.dart';
import 'package:app/features/attendance/data/attendance_views_providers.dart';
import 'package:app/features/attendance/data/attendance_views_repository.dart';
import 'package:app/features/attendance/domain/attendance_views.dart';
import 'package:app/features/attendance/presentation/admin_holidays_screen.dart';
import 'package:app/features/branches/data/branches_providers.dart';
import 'package:app/features/branches/domain/branch.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeViewsRepository extends Fake implements AttendanceViewsRepository {
  List<AttendanceHoliday> holidays = const [];
  Object? createError;
  AttendanceHoliday? created;
  String? createdScope;
  List<String>? createdBranchIds;
  String? deletedId;
  String? requestedBranchId;

  @override
  Future<AttendanceHoliday> createHoliday({
    required String date,
    required String name,
    String scope = 'all',
    List<String> branchIds = const [],
  }) async {
    if (createError case final error?) throw error;
    createdScope = scope;
    createdBranchIds = branchIds;
    return created = AttendanceHoliday(
      id: date,
      date: date,
      name: name,
      scope: scope,
      branchIds: branchIds,
    );
  }

  @override
  Future<void> deleteHoliday(String date) async {
    deletedId = date;
  }

  @override
  Future<List<AttendanceHoliday>> listHolidays(
    String year, {
    String? branchId,
  }) async {
    requestedBranchId = branchId;
    return holidays;
  }
}

const _branches = [
  Branch(
    id: 'branch-a',
    name: 'Branch A',
    state: 'Karnataka',
    lat: 0,
    lng: 0,
    radiusMeters: 100,
    status: BranchStatus.active,
    createdAt: '',
    updatedAt: '',
  ),
];

Widget _app(_FakeViewsRepository repository) {
  return ProviderScope(
    overrides: [
      attendanceViewsRepositoryProvider.overrideWithValue(repository),
      attendanceServerTodayProvider.overrideWith((ref) async => '2026-10-13'),
      branchesProvider('active').overrideWith((ref) async => _branches),
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
        AttendanceHoliday(id: 'later', date: '2026-10-20', name: 'Later'),
        AttendanceHoliday(id: 'earlier', date: '2026-10-01', name: 'Earlier'),
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

  testWidgets('resolves the state shortcut to selected branch IDs', (
    tester,
  ) async {
    final repository = _FakeViewsRepository();
    await tester.pumpWidget(_app(repository));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('add-holiday')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('holiday-name')),
      'State day',
    );
    await tester.tap(find.text('All branches').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Every branch in a state'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('holiday-state')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Karnataka').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(repository.createdScope, 'branches');
    expect(repository.createdBranchIds, ['branch-a']);
  });

  testWidgets('confirms deletion before removing a holiday', (tester) async {
    final repository = _FakeViewsRepository()
      ..holidays = const [
        AttendanceHoliday(
          id: '2026-10-08',
          date: '2026-10-08',
          name: 'Company day',
        ),
      ];
    await tester.pumpWidget(_app(repository));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('delete-holiday-2026-10-08')));
    await tester.pumpAndSettle();
    expect(find.text('Delete holiday?'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('confirm-delete-holiday')));
    await tester.pumpAndSettle();
    expect(repository.deletedId, '2026-10-08');
  });

  testWidgets('filters by branch and can clear the filter', (tester) async {
    final repository = _FakeViewsRepository();
    await tester.pumpWidget(_app(repository));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('holiday-branch-filter')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Branch A · Karnataka').last);
    await tester.pumpAndSettle();
    expect(repository.requestedBranchId, 'branch-a');
    await tester.tap(find.byKey(const ValueKey('clear-holiday-filter')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('clear-holiday-filter')), findsNothing);
    expect(find.text('All holidays'), findsOneWidget);
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
