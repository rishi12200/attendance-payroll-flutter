import 'package:app/features/attendance/data/attendance_views_providers.dart';
import 'package:app/features/attendance/domain/attendance_views.dart';
import 'package:app/features/leave/presentation/employee_holidays_section.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('shows own holiday names, scope and server-today marker', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          attendanceServerTodayProvider.overrideWith(
            (ref) async => '2026-10-13',
          ),
          myHolidaysProvider('2026').overrideWith(
            (ref) async => const [
              AttendanceHoliday(
                id: 'old',
                date: '2026-10-01',
                name: 'Past day',
              ),
              AttendanceHoliday(
                id: 'today',
                date: '2026-10-13',
                name: 'Founders day',
                scope: 'branches',
              ),
              AttendanceHoliday(
                id: 'next',
                date: '2026-12-25',
                name: 'Winter holiday',
              ),
            ],
          ),
        ],
        child: const MaterialApp(
          home: Scaffold(body: EmployeeHolidaysSection()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Founders day'), findsOneWidget);
    expect(find.textContaining('Your branch'), findsOneWidget);
    expect(find.text('Today'), findsOneWidget);
    await tester.drag(find.byType(ListView), const Offset(0, -500));
    await tester.pumpAndSettle();
    expect(find.text('Upcoming'), findsOneWidget);
    expect(find.textContaining('All branches'), findsWidgets);
    expect(find.text('branch-a'), findsNothing);
  });
}
