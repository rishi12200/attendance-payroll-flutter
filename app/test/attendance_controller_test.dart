import 'dart:async';

import 'package:app/core/api/app_exception.dart';
import 'package:app/features/attendance/data/attendance_providers.dart';
import 'package:app/features/attendance/data/attendance_repository.dart';
import 'package:app/features/attendance/data/install_id_store.dart';
import 'package:app/features/attendance/domain/attendance.dart';
import 'package:app/features/attendance/domain/attendance_controller.dart';
import 'package:app/features/branches/data/location_providers.dart';
import 'package:app/features/branches/domain/branch.dart';
import 'package:app/features/branches/domain/location_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const _position = LocationSuccess(
  latitude: 13,
  longitude: 80,
  accuracy: 10,
);

const _branch = Branch(
  id: 'branch-1',
  name: 'Chennai',
  state: 'Tamil Nadu',
  lat: 13,
  lng: 80,
  radiusMeters: 100,
  status: BranchStatus.active,
  createdAt: '',
  updatedAt: '',
);

class _FakeRepository implements AttendanceRepository {
  _FakeRepository(this.responses);

  final List<MonthAttendance> responses;
  final requests = <String>[];
  final payloads = <Map<String, Object?>>[];
  Object? punchError;
  int _next = 0;

  @override
  Future<MonthAttendance> getMyMonth(String month) async {
    requests.add(month);
    if (_next < responses.length) return responses[_next++];
    return responses.last;
  }

  @override
  Future<CheckInResult> checkIn(Map<String, Object?> payload) async {
    payloads.add(payload);
    if (punchError case final error?) throw error;
    return const CheckInResult(
      date: '2026-10-07',
      status: 'P',
      inTime: '2026-10-07T09:00:00.000Z',
      branchId: 'branch-1',
      branchName: 'Chennai',
      distanceMeters: 0,
    );
  }

  @override
  Future<CheckOutResult> checkOut(Map<String, Object?> payload) async {
    payloads.add(payload);
    if (punchError case final error?) throw error;
    return const CheckOutResult(
      date: '2026-10-07',
      inTime: '2026-10-07T09:00:00.000Z',
      outTime: '2026-10-07T17:00:00.000Z',
      workedMinutes: 480,
      branchId: 'branch-1',
      branchName: 'Chennai',
      distanceMeters: 0,
    );
  }
}

class _FakeLocationService implements LocationService {
  _FakeLocationService(this.result);

  LocationResult result;
  int calls = 0;
  LocationFailureReason? opened;
  Completer<LocationResult>? pending;

  @override
  Future<LocationResult> getCurrentPosition() {
    calls++;
    return pending?.future ?? Future.value(result);
  }

  @override
  Future<bool> openSettings(LocationFailureReason reason) async {
    opened = reason;
    return true;
  }
}

class _FakeInstallIdStore implements InstallIdStore {
  @override
  Future<String> getOrCreate() async => 'stable-install-id';
}

MonthAttendance _month({
  String month = '2026-10',
  String today = '2026-10-07',
  String serverTime = '2026-10-07T12:00:00.000Z',
  Map<String, AttendanceDay> days = const {},
}) => MonthAttendance(
  month: month,
  today: today,
  serverTime: serverTime,
  days: days,
);

ProviderContainer _container({
  required _FakeRepository repository,
  required _FakeLocationService location,
  required DateTime Function() clock,
}) => ProviderContainer(
  overrides: [
    attendanceRepositoryProvider.overrideWithValue(repository),
    locationServiceProvider.overrideWithValue(location),
    installIdStoreProvider.overrideWithValue(_FakeInstallIdStore()),
    attendanceClockProvider.overrideWithValue(clock),
    employeeBranchesProvider.overrideWith((ref) async => [_branch]),
  ],
);

Future<void> _settleInitialLoad(ProviderContainer container) async {
  for (var attempt = 0; attempt < 20; attempt++) {
    await Future<void>.delayed(Duration.zero);
    if (container.read(attendanceControllerProvider) is! AttendanceLoading) {
      return;
    }
  }
  fail('Attendance controller did not finish initial loading.');
}

void main() {
  test('initial load uses server date and restores a not-checked-in state', () async {
    final repository = _FakeRepository([_month()]);
    final container = _container(
      repository: repository,
      location: _FakeLocationService(_position),
      clock: () => DateTime(2035, 1, 1),
    );
    addTearDown(container.dispose);

    await _settleInitialLoad(container);
    final state = container.read(attendanceControllerProvider);
    expect(state, isA<AttendanceNotCheckedIn>());
    expect((state as AttendanceNotCheckedIn).today, '2026-10-07');
    expect(repository.requests, ['2035-01', '2026-10']);
  });

  test('restores open and completed server attendance states', () async {
    final openRepository = _FakeRepository([
      _month(
        days: {
          '2026-10-07': const AttendanceDay(
            status: 'P',
            inTime: '2026-10-07T09:00:00.000Z',
            inBranchId: 'branch-1',
          ),
        },
      ),
    ]);
    final openContainer = _container(
      repository: openRepository,
      location: _FakeLocationService(_position),
      clock: () => DateTime(2026, 10),
    );
    addTearDown(openContainer.dispose);
    await _settleInitialLoad(openContainer);
    expect(openContainer.read(attendanceControllerProvider), isA<AttendanceCheckedIn>());
    expect(
      (openContainer.read(attendanceControllerProvider) as AttendanceCheckedIn)
          .branchName,
      'Chennai',
    );

    final completedContainer = _container(
      repository: _FakeRepository([
        _month(
          days: {
            '2026-10-07': const AttendanceDay(
              status: 'P',
              inTime: '2026-10-07T09:00:00.000Z',
              outTime: '2026-10-07T17:00:00.000Z',
              workedMinutes: 480,
            ),
          },
        ),
      ]),
      location: _FakeLocationService(_position),
      clock: () => DateTime(2026, 10),
    );
    addTearDown(completedContainer.dispose);
    await _settleInitialLoad(completedContainer);
    expect(
      completedContainer.read(attendanceControllerProvider),
      isA<AttendanceCompleted>(),
    );
  });

  test('loads the prior month on server month boundary and checks out yesterday', () async {
    final repository = _FakeRepository([
      _month(
        today: '2026-10-01',
        serverTime: '2026-10-01T01:00:00.000Z',
      ),
      _month(
        month: '2026-09',
        today: '2026-10-01',
        serverTime: '2026-10-01T01:00:00.000Z',
        days: {
          '2026-09-30': const AttendanceDay(
            status: 'P',
            inTime: '2026-09-30T20:00:00.000Z',
            inBranchId: 'branch-1',
          ),
        },
      ),
      _month(
        today: '2026-10-01',
        serverTime: '2026-10-01T01:00:00.000Z',
      ),
      _month(
        month: '2026-09',
        today: '2026-10-01',
        serverTime: '2026-10-01T01:00:00.000Z',
        days: {
          '2026-09-30': const AttendanceDay(
            status: 'P',
            inTime: '2026-09-30T20:00:00.000Z',
            outTime: '2026-10-01T01:00:00.000Z',
            workedMinutes: 300,
            inBranchId: 'branch-1',
          ),
        },
      ),
    ]);
    final container = _container(
      repository: repository,
      location: _FakeLocationService(_position),
      clock: () => DateTime(2026, 10),
    );
    addTearDown(container.dispose);
    await _settleInitialLoad(container);

    expect(repository.requests, ['2026-10', '2026-09']);
    expect(container.read(attendanceControllerProvider), isA<AttendanceCheckedIn>());
    await container.read(attendanceControllerProvider.notifier).checkOut();
    expect(repository.payloads.single['deviceId'], 'stable-install-id');
    expect(
      container.read(attendanceControllerProvider),
      isA<AttendanceCompleted>(),
    );
  });

  test('check-in sends only current location, device id, and mocked flag', () async {
    final repository = _FakeRepository([
      _month(),
      _month(
        days: {
          '2026-10-07': const AttendanceDay(
            status: 'P',
            inTime: '2026-10-07T09:00:00.000Z',
            inBranchId: 'branch-1',
          ),
        },
      ),
    ]);
    final container = _container(
      repository: repository,
      location: _FakeLocationService(
        const LocationSuccess(
          latitude: 13,
          longitude: 80,
          accuracy: 10,
          isMocked: true,
        ),
      ),
      clock: () => DateTime(2026, 10),
    );
    addTearDown(container.dispose);
    await _settleInitialLoad(container);

    await container.read(attendanceControllerProvider.notifier).checkIn();
    expect(repository.payloads.single, {
      'lat': 13.0,
      'lng': 80.0,
      'accuracy': 10.0,
      'deviceId': 'stable-install-id',
      'isMocked': true,
    });
    expect(container.read(attendanceControllerProvider), isA<AttendanceCheckedIn>());
  });

  test('ignores a second punch while location acquisition is pending', () async {
    final location = _FakeLocationService(_position)
      ..pending = Completer<LocationResult>();
    final container = _container(
      repository: _FakeRepository([_month()]),
      location: location,
      clock: () => DateTime(2026, 10),
    );
    addTearDown(container.dispose);
    await _settleInitialLoad(container);

    final controller = container.read(attendanceControllerProvider.notifier);
    final first = controller.checkIn();
    final second = controller.checkIn();
    await second;
    expect(location.calls, 1);
    location.pending!.complete(_position);
    await first;
  });

  test('refreshes from server after duplicate or missing punch conflicts', () async {
    final repository = _FakeRepository([_month(), _month()]);
    repository.punchError = const AppException(
      code: 'ALREADY_CHECKED_IN',
      message: 'Already checked in.',
      details: {},
      statusCode: 409,
    );
    final container = _container(
      repository: repository,
      location: _FakeLocationService(_position),
      clock: () => DateTime(2026, 10),
    );
    addTearDown(container.dispose);
    await _settleInitialLoad(container);
    await container.read(attendanceControllerProvider.notifier).checkIn();

    expect(repository.requests.length, 2);
    expect(container.read(attendanceControllerProvider), isA<AttendanceNotCheckedIn>());
    expect(
      container.read(attendanceControllerProvider).feedback,
      'Already checked in.',
    );
  });

  test('location failure reasons have messages and settings action support', () async {
    for (final reason in LocationFailureReason.values) {
      final location = _FakeLocationService(LocationFailure(reason));
      final container = _container(
        repository: _FakeRepository([_month()]),
        location: location,
        clock: () => DateTime(2026, 10),
      );
      await _settleInitialLoad(container);
      await container.read(attendanceControllerProvider.notifier).checkIn();
      final state = container.read(attendanceControllerProvider);
      expect(state.feedback, isNotEmpty);
      if (reason == LocationFailureReason.serviceDisabled ||
          reason == LocationFailureReason.permissionDeniedForever) {
        await location.openSettings(reason);
        expect(location.opened, reason);
      }
      container.dispose();
    }
  });

  test('maps backend attendance errors to friendly messages', () {
    AppException error(String code, Map<String, Object?> details, {int status = 422}) =>
        AppException(
          code: code,
          message: 'Server fallback.',
          details: details,
          statusCode: status,
        );
    expect(
      attendanceErrorMessage(
        error('OUTSIDE_GEOFENCE', {
          'distanceMeters': 1200,
          'radiusMeters': 332,
          'nearestBranchName': 'Thoraipakkam',
        }),
      ),
      'You are 1.2 km from Thoraipakkam; you need to be within 332 m.',
    );
    expect(
      attendanceErrorMessage(
        error('ACCURACY_TOO_LOW', {'accuracy': 150}),
      ),
      'GPS accuracy is too low (150 m). Move to an open area and try again.',
    );
    expect(attendanceErrorMessage(error('MOCK_LOCATION', {})), 'Mock locations are not allowed.');
    expect(
      attendanceErrorMessage(error('NO_BRANCH_ASSIGNED', {})),
      'No branch is assigned to you yet. Ask your admin.',
    );
    expect(
      attendanceErrorMessage(error('MONTH_LOCKED', {})),
      'Server fallback.',
    );
    expect(
      attendanceErrorMessage(error('FORBIDDEN', {}, status: 403)),
      "Your account can't check in. Contact your admin.",
    );
  });
}
