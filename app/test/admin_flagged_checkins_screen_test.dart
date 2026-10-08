import 'package:app/core/api/app_exception.dart';
import 'package:app/features/attendance/data/attendance_views_providers.dart';
import 'package:app/features/attendance/domain/attendance_helpers.dart';
import 'package:app/features/attendance/domain/attendance_views.dart';
import 'package:app/features/attendance/presentation/admin_flagged_checkins_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

({String? from, String? to}) _initialRange() {
  final today = DateTime.parse(
    '${istDateOf(DateTime.now().toUtc().toIso8601String())}T00:00:00Z',
  );
  final start = today.subtract(const Duration(days: 6));
  String date(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-'
      '${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')}';
  return (from: date(start), to: date(today));
}

const _flagged = FlaggedCheckin(
  id: 'attempt-1',
  empCode: 'EMP001',
  name: 'Asha',
  type: 'in',
  date: '2026-10-08',
  serverTime: '2026-10-08T07:19:12.000Z',
  rejectReason: 'OUTSIDE_GEOFENCE',
  nearestBranchName: 'Chennai Office',
  distanceMeters: 1250,
  accuracy: 15,
  isMocked: false,
  deviceId: 'install-id',
);

Widget _app(Future<List<FlaggedCheckin>> Function()? load) => ProviderScope(
  overrides: [
    flaggedCheckinsProvider(_initialRange()).overrideWith((ref) => load!()),
  ],
  child: const MaterialApp(home: AdminFlaggedCheckinsScreen()),
);

void main() {
  testWidgets('shows an empty state for the default last-seven-day range', (
    tester,
  ) async {
    await tester.pumpWidget(_app(() async => []));
    await tester.pumpAndSettle();

    expect(
      find.text('No flagged check-ins in this date range.'),
      findsOneWidget,
    );
  });

  testWidgets('shows employee, IST time, readable reason and branch distance', (
    tester,
  ) async {
    await tester.pumpWidget(_app(() async => [_flagged]));
    await tester.pumpAndSettle();

    expect(find.text('Asha'), findsOneWidget);
    expect(find.text('EMP001 · Outside branch geofence'), findsOneWidget);
    expect(find.text('Thu, 8 Oct 2026 12:49 PM'), findsOneWidget);
    expect(find.text('1.3 km from Chennai Office'), findsOneWidget);
    expect(find.text('Check-in'), findsOneWidget);
  });

  testWidgets('shows API range errors', (tester) async {
    await tester.pumpWidget(
      _app(
        () async => throw const AppException(
          code: 'INVALID_DATE_RANGE',
          message: 'Choose a maximum 31-day range.',
          details: {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Choose a maximum 31-day range.'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
  });
}
