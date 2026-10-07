import 'dart:async';

import 'package:app/core/api/app_exception.dart';
import 'package:app/core/auth/auth_providers.dart';
import 'package:app/features/auth/domain/user_profile.dart';
import 'package:app/features/employees/data/employee_repository.dart';
import 'package:app/features/employees/data/employees_providers.dart';
import 'package:app/features/employees/domain/employee.dart';
import 'package:app/features/employees/domain/employee_dates.dart';
import 'package:app/features/employees/domain/salary_revision.dart';
import 'package:app/features/employees/presentation/add_employee_screen.dart';
import 'package:app/features/employees/presentation/employee_detail_screen.dart';
import 'package:app/features/employees/presentation/employee_list_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const employee = Employee(
  uid: 'employee-1',
  empCode: 'EMP001',
  name: 'Employee One',
  email: 'one@example.com',
  role: 'employee',
  status: EmployeeStatus.active,
  doj: '2026-10-01',
  createdAt: '2026-10-01T00:00:00.000Z',
  updatedAt: '2026-10-01T00:00:00.000Z',
  designation: 'Associate',
);

class FakeEmployeeRepository implements EmployeeRepository {
  int deactivateCalls = 0;
  String? deactivationDate;

  @override
  Future<Employee> createEmployee({
    required String name,
    required String email,
    required String tempPassword,
    required String doj,
    required int monthlyCtcPaise,
    String? phone,
    String? designation,
  }) async => employee;

  @override
  Future<Employee> deactivate(String id, {String? dol}) async {
    deactivateCalls++;
    deactivationDate = dol;
    return employee;
  }

  @override
  Future<Employee> getEmployee(String id) async => employee;

  @override
  Future<List<Employee>> listEmployees({String status = 'active'}) async => [
    employee,
  ];

  @override
  Future<List<SalaryRevision>> listSalary(String id) async => [];

  @override
  Future<SalaryRevision> addSalaryRevision(
    String id,
    String effectiveFrom,
    int monthlyCtcPaise,
  ) async => SalaryRevision(
    empId: id,
    effectiveFrom: effectiveFrom,
    monthlyCtcPaise: monthlyCtcPaise,
  );

  @override
  Future<Employee> reactivate(String id) async => employee;

  @override
  Future<Employee> updateEmployee(
    String id,
    Map<String, Object?> fields,
  ) async => employee;
}

Widget _app(Widget child) => ProviderScope(child: MaterialApp(home: child));

void main() {
  group('employee list states', () {
    testWidgets('shows loading state', (tester) async {
      final pending = Completer<List<Employee>>();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            employeesProvider('active').overrideWith((ref) => pending.future),
          ],
          child: const MaterialApp(home: EmployeeListScreen()),
        ),
      );
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('shows empty state', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            employeesProvider('active').overrideWith((ref) async => []),
          ],
          child: const MaterialApp(home: EmployeeListScreen()),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('No employees found.'), findsOneWidget);
    });

    testWidgets('shows server error and retries', (tester) async {
      var requests = 0;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            employeesProvider('active').overrideWith((ref) async {
              requests++;
              throw const AppException(
                code: 'FAILED',
                message: 'Employee service unavailable.',
                details: {},
              );
            }),
          ],
          child: const MaterialApp(home: EmployeeListScreen()),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Employee service unavailable.'), findsOneWidget);
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(requests, 2);
    });

    testWidgets('shows data and filters by search', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            employeesProvider('active').overrideWith((ref) async => [employee]),
          ],
          child: const MaterialApp(home: EmployeeListScreen()),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Employee One'), findsOneWidget);
      expect(find.text('EMP001'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'someone-not-found');
      await tester.pumpAndSettle();
      expect(find.text('No employees found.'), findsOneWidget);
    });
  });

  group('add employee validation', () {
    testWidgets('requires name, email, password, and positive amount', (
      tester,
    ) async {
      await tester.pumpWidget(_app(const AddEmployeeScreen()));
      await tester.ensureVisible(find.text('Create employee'));
      await tester.tap(find.text('Create employee'));
      await tester.pumpAndSettle();

      expect(find.text('Name is required.'), findsOneWidget);
      expect(find.text('Email is required.'), findsOneWidget);
      expect(find.text('Password is required.'), findsOneWidget);
      expect(
        find.text('Enter a positive amount with at most 2 decimals.'),
        findsOneWidget,
      );
    });

    testWidgets('rejects a short password and malformed amount', (
      tester,
    ) async {
      await tester.pumpWidget(_app(const AddEmployeeScreen()));
      final fields = find.byType(TextFormField);
      await tester.enterText(fields.at(0), 'Employee');
      await tester.enterText(fields.at(1), 'employee@example.com');
      await tester.enterText(fields.at(2), 'short');
      await tester.enterText(fields.at(5), '10.999');
      await tester.ensureVisible(find.text('Create employee'));
      await tester.tap(find.text('Create employee'));
      await tester.pumpAndSettle();

      expect(
        find.text('Password must be at least 8 characters.'),
        findsOneWidget,
      );
      expect(
        find.text('Enter a positive amount with at most 2 decimals.'),
        findsOneWidget,
      );
    });
  });

  testWidgets('deactivate requires confirmation and sends the selected date', (
    tester,
  ) async {
    final repository = FakeEmployeeRepository();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          employeeRepositoryProvider.overrideWithValue(repository),
          employeeProvider('employee-1').overrideWith((ref) async => employee),
          salaryHistoryProvider('employee-1').overrideWith((ref) async => []),
          currentProfileProvider.overrideWith(
            (ref) async => const UserProfile(
              uid: 'admin-1',
              name: 'Admin',
              email: 'admin@example.com',
              role: UserRole.admin,
            ),
          ),
        ],
        child: const MaterialApp(home: EmployeeDetailScreen(id: 'employee-1')),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Deactivate'));
    await tester.pumpAndSettle();
    expect(find.text('Deactivate employee?'), findsOneWidget);
    expect(repository.deactivateCalls, 0);

    await tester.tap(find.text('Deactivate').last);
    await tester.pumpAndSettle();
    expect(repository.deactivateCalls, 1);
    expect(repository.deactivationDate, todayIST());
  });
}
