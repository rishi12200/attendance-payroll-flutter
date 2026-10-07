import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/auth_providers.dart';
import '../domain/employee.dart';
import '../domain/salary_revision.dart';
import 'employee_repository.dart';

final employeeRepositoryProvider = Provider<EmployeeRepository>(
  (ref) => ApiEmployeeRepository(ref.watch(apiClientProvider)),
);

final employeesProvider = FutureProvider.family<List<Employee>, String>(
  (ref, status) =>
      ref.watch(employeeRepositoryProvider).listEmployees(status: status),
  retry: (_, _) => null,
);

final employeeProvider = FutureProvider.family<Employee, String>(
  (ref, id) => ref.watch(employeeRepositoryProvider).getEmployee(id),
  retry: (_, _) => null,
);

final salaryHistoryProvider =
    FutureProvider.family<List<SalaryRevision>, String>(
      (ref, id) => ref.watch(employeeRepositoryProvider).listSalary(id),
      retry: (_, _) => null,
    );
