import 'package:app/core/api/app_exception.dart';
import 'package:app/core/auth/auth_providers.dart';
import 'package:app/features/attendance/data/attendance_providers.dart';
import 'package:app/features/attendance/data/attendance_repository.dart';
import 'package:app/features/attendance/data/install_id_store.dart';
import 'package:app/features/attendance/domain/attendance.dart';
import 'package:app/features/attendance/domain/attendance_controller.dart';
import 'package:app/features/attendance/presentation/employee_attendance_screen.dart';
import 'package:app/features/auth/domain/user_profile.dart';
import 'package:app/features/branches/data/location_providers.dart';
import 'package:app/features/branches/domain/branch.dart';
import 'package:app/features/branches/domain/location_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const _branch = Branch(
  id: 'branch-1',
  name: 'Thoraipakkam',
  state: 'Tamil Nadu',
  lat: 13,
  lng: 80,
  radiusMeters: 332,
  status: BranchStatus.active,
  createdAt: '',
  updatedAt: '',
);

MonthAttendance _month({
  Map<String, AttendanceDay> days = const {},
}) => MonthAttendance(
  month: '2026-10',
  today: '2026-10-07',
  serverTime: '2026-10-07T12:00:00.000Z',
  days: days,
);

class _FakeAttendanceRepository implements AttendanceRepository {
  _FakeAttendanceRepository(this.response);

  MonthAttendance response;
  AppException? punchError;

  @override
  Future<MonthAttendance> getMyMonth(String month) async => response;

  @override
  Future<CheckInResult> checkIn(Map<String, Object?> payload) async {
    if (punchError case final error?) throw error;
    response = _month(
      days: {
        '2026-10-07': const AttendanceDay(
          status: 'P',
          inTime: '2026-10-07T09:00:00.000Z',
          inBranchId: 'branch-1',
        ),
      },
    );
    return const CheckInResult(
      date: '2026-10-07',
      status: 'P',
      inTime: '2026-10-07T09:00:00.000Z',
      branchId: 'branch-1',
      branchName: 'Thoraipakkam',
      distanceMeters: 0,
    );
  }

  @override
  Future<CheckOutResult> checkOut(Map<String, Object?> payload) async {
    if (punchError case final error?) throw error;
    response = _month(
      days: {
        '2026-10-07': const AttendanceDay(
          status: 'P',
          inTime: '2026-10-07T09:00:00.000Z',
          outTime: '2026-10-07T12:00:00.000Z',
          workedMinutes: 180,
        ),
      },
    );
    return const CheckOutResult(
      date: '2026-10-07',
      inTime: '2026-10-07T09:00:00.000Z',
      outTime: '2026-10-07T12:00:00.000Z',
      workedMinutes: 180,
      branchId: 'branch-1',
      branchName: 'Thoraipakkam',
      distanceMeters: 0,
    );
  }
}

class _FakeLocationService implements LocationService {
  _FakeLocationService(this.result);

  final LocationResult result;
  LocationFailureReason? opened;

  @override
  Future<LocationResult> getCurrentPosition() async => result;

  @override
  Future<bool> openSettings(LocationFailureReason reason) async {
    opened = reason;
    return true;
  }
}

class _FakeInstallIdStore implements InstallIdStore {
  @override
  Future<String> getOrCreate() async => 'install-id';
}

Future<_FakeLocationService> _pumpScreen(
  WidgetTester tester, {
  required _FakeAttendanceRepository repository,
  required List<Branch> branches,
  required LocationResult location,
}) async {
  final locationService = _FakeLocationService(location);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        currentProfileProvider.overrideWith(
          (ref) async => const UserProfile(
            uid: 'employee-1',
            name: 'Test Employee',
            email: 'employee@example.com',
            role: UserRole.employee,
          ),
        ),
        attendanceRepositoryProvider.overrideWithValue(repository),
        installIdStoreProvider.overrideWithValue(_FakeInstallIdStore()),
        attendanceClockProvider.overrideWithValue(() => DateTime(2026, 10)),
        employeeBranchesProvider.overrideWith((ref) async => branches),
        locationServiceProvider.overrideWithValue(locationService),
      ],
      child: const MaterialApp(home: EmployeeAttendanceScreen()),
    ),
  );
  await tester.pumpAndSettle();
  return locationService;
}

void main() {
  testWidgets('shows not-checked-in state and enables check-in with a branch', (
    tester,
  ) async {
    await _pumpScreen(
      tester,
      repository: _FakeAttendanceRepository(_month()),
      branches: [_branch],
      location: const LocationSuccess(
        latitude: 13,
        longitude: 80,
        accuracy: 10,
      ),
    );
    expect(find.text('Test Employee'), findsOneWidget);
    expect(find.text('October 7, 2026'), findsOneWidget);
    expect(find.text('Not checked in'), findsOneWidget);
    final button = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Check in'),
    );
    expect(button.onPressed, isNotNull);
    expect(find.textContaining('You are about'), findsOneWidget);
  });

  testWidgets('shows checked-in state and enables check-out', (tester) async {
    await _pumpScreen(
      tester,
      repository: _FakeAttendanceRepository(
        _month(
          days: {
            '2026-10-07': const AttendanceDay(
              status: 'P',
              inTime: '2026-10-07T09:00:00.000Z',
              inBranchId: 'branch-1',
            ),
          },
        ),
      ),
      branches: [_branch],
      location: const LocationSuccess(
        latitude: 13,
        longitude: 80,
        accuracy: 10,
      ),
    );
    expect(find.text('Checked in at 02:30 PM'), findsOneWidget);
    expect(find.text('Thoraipakkam'), findsOneWidget);
    expect(
      tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Check out'),
      ).onPressed,
      isNotNull,
    );
  });

  testWidgets('shows completed state and disables the done button', (tester) async {
    await _pumpScreen(
      tester,
      repository: _FakeAttendanceRepository(
        _month(
          days: {
            '2026-10-07': const AttendanceDay(
              status: 'P',
              inTime: '2026-10-07T09:00:00.000Z',
              outTime: '2026-10-07T12:00:00.000Z',
              workedMinutes: 180,
            ),
          },
        ),
      ),
      branches: [_branch],
      location: const LocationSuccess(
        latitude: 13,
        longitude: 80,
        accuracy: 10,
      ),
    );
    expect(find.text('Done for today'), findsWidgets);
    expect(find.text('Worked: 3 h'), findsOneWidget);
    expect(
      tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Done for today'),
      ).onPressed,
      isNull,
    );
  });

  testWidgets('no assigned branches shows guidance and disables check-in', (
    tester,
  ) async {
    await _pumpScreen(
      tester,
      repository: _FakeAttendanceRepository(_month()),
      branches: const [],
      location: const LocationSuccess(
        latitude: 13,
        longitude: 80,
        accuracy: 10,
      ),
    );
    expect(
      find.text('No branch is assigned to you yet. Ask your admin.'),
      findsWidgets,
    );
    expect(
      tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Check in'),
      ).onPressed,
      isNull,
    );
  });

  testWidgets('location failure shows a message and opens app settings', (
    tester,
  ) async {
    final location = await _pumpScreen(
      tester,
      repository: _FakeAttendanceRepository(_month()),
      branches: [_branch],
      location: const LocationFailure(
        LocationFailureReason.permissionDeniedForever,
      ),
    );
    expect(
      find.textContaining('Location permission is blocked'),
      findsOneWidget,
    );
    await tester.tap(find.text('Open app settings'));
    await tester.pump();
    expect(location.opened, LocationFailureReason.permissionDeniedForever);
  });

  testWidgets('disabled location services offer location settings', (
    tester,
  ) async {
    final location = await _pumpScreen(
      tester,
      repository: _FakeAttendanceRepository(_month()),
      branches: [_branch],
      location: const LocationFailure(
        LocationFailureReason.serviceDisabled,
      ),
    );
    expect(find.textContaining('Location services are off'), findsOneWidget);
    await tester.tap(find.text('Open location settings'));
    await tester.pump();
    expect(location.opened, LocationFailureReason.serviceDisabled);
  });

  testWidgets('shows a friendly backend location rejection', (tester) async {
    final repository = _FakeAttendanceRepository(_month())
      ..punchError = const AppException(
        code: 'OUTSIDE_GEOFENCE',
        message: 'Outside the geofence.',
        details: {
          'distanceMeters': 1200,
          'radiusMeters': 332,
          'nearestBranchName': 'Thoraipakkam',
        },
        statusCode: 422,
      );
    await _pumpScreen(
      tester,
      repository: repository,
      branches: [_branch],
      location: const LocationSuccess(
        latitude: 13,
        longitude: 80,
        accuracy: 10,
      ),
    );
    await tester.tap(find.text('Check in'));
    await tester.pumpAndSettle();
    expect(
      find.text(
        'You are 1.2 km from Thoraipakkam; you need to be within 332 m.',
      ),
      findsOneWidget,
    );
  });
}
