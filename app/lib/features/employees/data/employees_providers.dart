import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/auth_providers.dart';
import '../domain/employee.dart';
import '../domain/salary_revision.dart';
import 'employee_repository.dart';

final employeeRepositoryProvider = Provider<EmployeeRepository>(
  (ref) => ApiEmployeeRepository(ref.watch(apiClientProvider)),
);

final employeesProvider =
    FutureProvider.family<List<Employee>, String>((ref, status) {
      return ref
          .watch(employeeRepositoryProvider)
          .listEmployees(status: status);
    });

final employeeProvider = FutureProvider.family<Employee, String>((ref, id) {
  return ref.watch(employeeRepositoryProvider).getEmployee(id);
});

final salaryHistoryProvider =
    FutureProvider.family<List<SalaryRevision>, String>((ref, id) {
      return ref.watch(employeeRepositoryProvider).listSalary(id);
    });
