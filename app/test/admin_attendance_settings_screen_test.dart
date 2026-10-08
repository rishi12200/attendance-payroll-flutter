import 'package:app/core/api/app_exception.dart';
import 'package:app/features/attendance/data/attendance_views_providers.dart';
import 'package:app/features/attendance/data/attendance_views_repository.dart';
import 'package:app/features/attendance/domain/attendance_views.dart';
import 'package:app/features/attendance/presentation/admin_attendance_settings_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeViewsRepository extends Fake implements AttendanceViewsRepository {
  Map<String, Object?>? changes;
  Object? error;

  @override
  Future<AttendanceSettings> updateSettings(
    Map<String, Object?> changes,
  ) async {
    this.changes = Map.of(changes);
    if (error case final value?) throw value;
    return AttendanceSettings(
      companyName: changes['companyName'] as String? ?? '',
      weeklyOffDays: (changes['weeklyOffDays'] as List<int>?) ?? const [0],
      perDayBasis: changes['perDayBasis'] as String? ?? 'calendar',
      maxAccuracyMeters: changes['maxAccuracyMeters'] as int? ?? 100,
      rejectMockLocation: changes['rejectMockLocation'] as bool? ?? true,
      enforceCheckoutLocation:
          changes['enforceCheckoutLocation'] as bool? ?? false,
    );
  }
}

const _settings = AttendanceSettings(
  companyName: 'Example Company',
  weeklyOffDays: [0],
  perDayBasis: 'calendar',
  maxAccuracyMeters: 100,
  rejectMockLocation: true,
  enforceCheckoutLocation: false,
);

Widget _app(_FakeViewsRepository repository) => ProviderScope(
  overrides: [
    attendanceViewsRepositoryProvider.overrideWithValue(repository),
    attendanceSettingsProvider.overrideWith((ref) async => _settings),
  ],
  child: const MaterialApp(home: AdminAttendanceSettingsScreen()),
);

void main() {
  testWidgets('renders settings and the past-month weekly-off note', (
    tester,
  ) async {
    await tester.pumpWidget(_app(_FakeViewsRepository()));
    await tester.pumpAndSettle();

    expect(find.text('Example Company'), findsOneWidget);
    expect(find.text('Maximum GPS accuracy: 100 m'), findsOneWidget);
    expect(
      find.text('Changing this also changes past months that are not locked.'),
      findsOneWidget,
    );
    expect(
      tester
          .widget<FilledButton>(
            find.byKey(const ValueKey('save-attendance-settings')),
          )
          .onPressed,
      isNull,
    );
  });

  testWidgets('sends only changed settings fields', (tester) async {
    final repository = _FakeViewsRepository();
    await tester.pumpWidget(_app(repository));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('weekly-off-6')));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView), const Offset(0, -400));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('save-attendance-settings')));
    await tester.pumpAndSettle();

    expect(repository.changes, {
      'weeklyOffDays': [0, 6],
    });
    expect(find.text('Attendance settings saved.'), findsOneWidget);
  });

  testWidgets('shows settings update errors from the server', (tester) async {
    final repository = _FakeViewsRepository()
      ..error = const AppException(
        code: 'VALIDATION_ERROR',
        message: 'The weekly off days are invalid.',
        details: {},
      );
    await tester.pumpWidget(_app(repository));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('weekly-off-6')));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView), const Offset(0, -400));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('save-attendance-settings')));
    await tester.pumpAndSettle();

    expect(find.text('The weekly off days are invalid.'), findsOneWidget);
  });
}
