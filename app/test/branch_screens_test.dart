import 'dart:async';

import 'package:app/core/api/app_exception.dart';
import 'package:app/features/branches/data/branch_repository.dart';
import 'package:app/features/branches/data/branches_providers.dart';
import 'package:app/features/branches/data/location_providers.dart';
import 'package:app/features/branches/domain/branch.dart';
import 'package:app/features/branches/domain/branch_assignment.dart';
import 'package:app/features/branches/domain/location_service.dart';
import 'package:app/features/branches/presentation/branch_assignment_fields.dart';
import 'package:app/features/branches/presentation/branch_form_screen.dart';
import 'package:app/features/branches/presentation/branch_list_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const _branch = Branch(
  id: 'branch-1',
  name: 'Chennai Office',
  address: '',
  state: 'Tamil Nadu',
  lat: 13.08,
  lng: 80.27,
  radiusMeters: 150,
  status: BranchStatus.active,
  createdAt: '2026-10-07T00:00:00.000Z',
  updatedAt: '2026-10-07T00:00:00.000Z',
);
const _otherBranch = Branch(
  id: 'branch-2',
  name: 'Coimbatore Office',
  state: 'Tamil Nadu',
  lat: 11.01,
  lng: 76.95,
  radiusMeters: 100,
  status: BranchStatus.active,
  createdAt: '2026-10-07T00:00:00.000Z',
  updatedAt: '2026-10-07T00:00:00.000Z',
);

class _FakeRepository implements BranchRepository {
  Object? lifecycleError;
  int deactivateCalls = 0;
  Map<String, Object?>? lastCreate;
  Map<String, Object?>? lastUpdate;

  @override
  Future<Branch> createBranch(Map<String, Object?> fields) async {
    lastCreate = fields;
    return _branch;
  }

  @override
  Future<Branch> deactivate(String id) async {
    deactivateCalls++;
    if (lifecycleError case final value?) throw value;
    return _branch;
  }

  @override
  Future<Branch> getBranch(String id) async => _branch;

  @override
  Future<List<Branch>> listBranches({String status = 'active'}) async => [
    _branch,
  ];

  @override
  Future<Branch> reactivate(String id) async => _branch;

  @override
  Future<Branch> updateBranch(String id, Map<String, Object?> fields) async {
    lastUpdate = fields;
    return _branch;
  }
}

class _FakeLocationService implements LocationService {
  _FakeLocationService(this.result);
  final LocationResult result;
  LocationFailureReason? openedSettingsFor;

  @override
  Future<LocationResult> getCurrentPosition() async => result;

  @override
  Future<bool> openSettings(LocationFailureReason reason) async {
    openedSettingsFor = reason;
    return true;
  }
}

Widget _scope(Widget child) => ProviderScope(child: MaterialApp(home: child));

Future<void> _scrollTo(WidgetTester tester, Finder target) async {
  await tester.drag(find.byType(SingleChildScrollView), const Offset(0, -400));
  await tester.pumpAndSettle();
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
}

void main() {
  group('branch list states', () {
    testWidgets('shows loading', (tester) async {
      final pending = Completer<List<Branch>>();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            branchesProvider('active').overrideWith((ref) => pending.future),
          ],
          child: const MaterialApp(home: BranchListScreen()),
        ),
      );
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('shows empty state', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            branchesProvider('active').overrideWith((ref) async => []),
          ],
          child: const MaterialApp(home: BranchListScreen()),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('No branches found.'), findsOneWidget);
    });

    testWidgets('shows server error and retry', (tester) async {
      var count = 0;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            branchesProvider('active').overrideWith((ref) async {
              count++;
              throw const AppException(
                code: 'FAILED',
                message: 'Branch service unavailable.',
                details: {},
              );
            }),
          ],
          child: const MaterialApp(home: BranchListScreen()),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Branch service unavailable.'), findsOneWidget);
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(count, 2);
    });

    testWidgets('shows branch data and search filters by state', (
      tester,
    ) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            branchesProvider('active')
                .overrideWith((ref) async => [_branch, _otherBranch]),
          ],
          child: const MaterialApp(home: BranchListScreen()),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Chennai Office'), findsOneWidget);
      expect(find.textContaining('100 m radius'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'Tamil Nadu');
      await tester.pumpAndSettle();
      expect(find.text('Coimbatore Office'), findsOneWidget);
    });
  });

  testWidgets('branch form validates required values and coordinate bounds', (
    tester,
  ) async {
    await tester.pumpWidget(_scope(const BranchFormScreen()));
    await tester.ensureVisible(find.text('Create branch'));
    await tester.tap(find.text('Create branch'));
    await tester.pumpAndSettle();
    expect(find.text('Name is required.'), findsOneWidget);
    expect(find.text('State is required.'), findsOneWidget);
    expect(find.text('Enter a latitude from -90 to 90.'), findsOneWidget);
    expect(find.text('Enter a longitude from -180 to 180.'), findsOneWidget);
  });

  testWidgets('branch assignment picker retries after a load error', (
    tester,
  ) async {
    var requests = 0;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          branchesProvider('active').overrideWith((ref) async {
            requests++;
            if (requests == 1) {
              throw const AppException(
                code: 'FAILED',
                message: 'Branches are temporarily unavailable.',
                details: {},
              );
            }
            return [_branch];
          }),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: BranchAssignmentFields(
              assignment: const BranchAssignment(
                primaryBranchId: null,
                allowedBranchIds: {},
              ),
              onChanged: (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Branches are temporarily unavailable.'), findsOneWidget);
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.text('Chennai Office'), findsOneWidget);
    expect(requests, 2);
  });

  testWidgets('uses current location and displays reported accuracy', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          locationServiceProvider.overrideWithValue(
            _FakeLocationService(
              const LocationSuccess(
                latitude: 13.0827,
                longitude: 80.2707,
                accuracy: 8,
              ),
            ),
          ),
        ],
        child: const MaterialApp(home: BranchFormScreen()),
      ),
    );
    await tester.tap(find.text('Use my current location'));
    await tester.pumpAndSettle();
    expect(find.text('Reported accuracy: 8 m'), findsOneWidget);
    final coordinateFields = tester
        .widgetList<TextFormField>(find.byType(TextFormField))
        .toList();
    expect(coordinateFields[3].controller!.text, '13.082700');
    expect(coordinateFields[4].controller!.text, '80.270700');
  });

  for (final (reason, message, hasAction)
      in <(LocationFailureReason, String, bool)>[
        (
          LocationFailureReason.serviceDisabled,
          'Location services are off. Turn them on to use your current location.',
          true,
        ),
        (
          LocationFailureReason.permissionDenied,
          'Location permission was denied. Allow access to use your current location.',
          false,
        ),
        (
          LocationFailureReason.permissionDeniedForever,
          'Location permission is blocked. Open app settings to allow access.',
          true,
        ),
        (
          LocationFailureReason.timeout,
          'Could not get a location fix within 15 seconds. Try again.',
          false,
        ),
        (
          LocationFailureReason.unknown,
          'Could not get your location. Check the device settings and try again.',
          false,
        ),
      ]) {
    testWidgets('location failure $reason has a clear message', (tester) async {
      final service = _FakeLocationService(LocationFailure(reason));
      await tester.pumpWidget(
        ProviderScope(
          overrides: [locationServiceProvider.overrideWithValue(service)],
          child: const MaterialApp(home: BranchFormScreen()),
        ),
      );
      await tester.tap(find.text('Use my current location'));
      await tester.pumpAndSettle();
      expect(find.text(message), findsWidgets);
      final settingsLabel = reason == LocationFailureReason.serviceDisabled
          ? 'Open location settings'
          : 'Open app settings';
      if (hasAction) {
        await tester.tap(find.text(settingsLabel));
        await tester.pumpAndSettle();
        expect(service.openedSettingsFor, reason);
      } else {
        expect(find.text(settingsLabel), findsNothing);
      }
    });
  }

  testWidgets('deactivation conflict displays server count and keeps branch', (
    tester,
  ) async {
    final repository = _FakeRepository()
      ..lifecycleError = const AppException(
        code: 'BRANCH_HAS_ACTIVE_EMPLOYEES',
        message: 'Cannot deactivate this branch while 3 active employee(s) are assigned to it.',
        details: {'activeEmployeeCount': 3},
        statusCode: 409,
      );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          branchProvider('branch-1').overrideWith((ref) async => _branch),
          branchRepositoryProvider.overrideWithValue(repository),
        ],
        child: const MaterialApp(home: BranchFormScreen(id: 'branch-1')),
      ),
    );
    await tester.pumpAndSettle();
    await _scrollTo(tester, find.text('Deactivate branch'));
    await tester.tap(find.text('Deactivate branch'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Deactivate').last);
    await tester.pumpAndSettle();
    expect(repository.deactivateCalls, 1);
    expect(
      find.text(
        'Cannot deactivate this branch while 3 active employee(s) are assigned to it.',
      ),
      findsWidgets,
    );
    expect(find.text('Deactivate branch'), findsOneWidget);
  });

  testWidgets('employee picker enforces primary selection rules', (
    tester,
  ) async {
    var assignment = const BranchAssignment(
      primaryBranchId: null,
      allowedBranchIds: {},
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          branchesProvider('active')
              .overrideWith((ref) async => [_branch, _otherBranch]),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) => BranchAssignmentFields(
                assignment: assignment,
                onChanged: (value) => setState(() => assignment = value),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('This employee cannot check in yet.'), findsOneWidget);
    await tester.tap(find.byType(DropdownButtonFormField<String?>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Chennai Office').last);
    await tester.pumpAndSettle();
    expect(assignment.allowedBranchIds, {'branch-1'});
    var tiles = tester.widgetList<CheckboxListTile>(
      find.byType(CheckboxListTile),
    );
    expect(tiles.first.onChanged, isNull);

    await tester.tap(find.byType(DropdownButtonFormField<String?>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('No primary branch').last);
    await tester.pumpAndSettle();
    expect(assignment.primaryBranchId, isNull);
    expect(assignment.allowedBranchIds, {'branch-1'});
    tiles = tester.widgetList<CheckboxListTile>(find.byType(CheckboxListTile));
    expect(tiles.first.onChanged, isNotNull);
  });
}
