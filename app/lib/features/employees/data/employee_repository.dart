import 'package:dio/dio.dart';

import '../../../core/api/api_client.dart';
import '../../../core/api/app_exception.dart';
import '../domain/employee.dart';
import '../domain/salary_revision.dart';

abstract interface class EmployeeRepository {
  Future<List<Employee>> listEmployees({String status = 'active'});
  Future<Employee> getEmployee(String id);
  Future<Employee> createEmployee({
    required String name,
    required String email,
    required String tempPassword,
    required String doj,
    required int monthlyCtcPaise,
    String? phone,
    String? designation,
  });
  Future<Employee> updateEmployee(String id, Map<String, Object?> fields);
  Future<List<SalaryRevision>> listSalary(String id);
  Future<SalaryRevision> addSalaryRevision(
    String id,
    String effectiveFrom,
    int monthlyCtcPaise,
  );
  Future<Employee> deactivate(String id, {String? dol});
  Future<Employee> reactivate(String id);
}

class ApiEmployeeRepository implements EmployeeRepository {
  const ApiEmployeeRepository(this._api);

  final ApiTransport _api;

  @override
  Future<List<Employee>> listEmployees({String status = 'active'}) =>
      _withApiErrors(() async {
        final response = await _api.getJson(
          '/employees',
          queryParameters: {'status': status},
        );
        if (response is! List) _invalidResponse();
        return response
            .map((item) => Employee.fromJson(_asJsonMap(item)))
            .toList(growable: false);
      });

  @override
  Future<Employee> getEmployee(String id) => _withApiErrors(() async {
    return Employee.fromJson(
      _asJsonMap(await _api.getJson('/employees/${Uri.encodeComponent(id)}')),
    );
  });

  @override
  Future<Employee> createEmployee({
    required String name,
    required String email,
    required String tempPassword,
    required String doj,
    required int monthlyCtcPaise,
    String? phone,
    String? designation,
  }) => _withApiErrors(() async {
    final body = <String, Object?>{
      'name': name,
      'email': email,
      'tempPassword': tempPassword,
      'doj': doj,
      'monthlyCtcPaise': monthlyCtcPaise,
      if (phone != null && phone.isNotEmpty) 'phone': phone,
      if (designation != null && designation.isNotEmpty)
        'designation': designation,
    };
    return Employee.fromJson(
      _asJsonMap(await _api.postJson('/employees', data: body)),
    );
  });

  @override
  Future<Employee> updateEmployee(String id, Map<String, Object?> fields) =>
      _withApiErrors(() async {
        return Employee.fromJson(
          _asJsonMap(
            await _api.patchJson(
              '/employees/${Uri.encodeComponent(id)}',
              data: fields,
            ),
          ),
        );
      });

  @override
  Future<List<SalaryRevision>> listSalary(String id) =>
      _withApiErrors(() async {
        final response = await _api.getJson(
          '/employees/${Uri.encodeComponent(id)}/salary',
        );
        if (response is! List) _invalidResponse();
        return response
            .map((item) => SalaryRevision.fromJson(_asJsonMap(item)))
            .toList(growable: false);
      });

  @override
  Future<SalaryRevision> addSalaryRevision(
    String id,
    String effectiveFrom,
    int monthlyCtcPaise,
  ) => _withApiErrors(() async {
    return SalaryRevision.fromJson(
      _asJsonMap(
        await _api.postJson(
          '/employees/${Uri.encodeComponent(id)}/salary',
          data: {
            'effectiveFrom': effectiveFrom,
            'monthlyCtcPaise': monthlyCtcPaise,
          },
        ),
      ),
    );
  });

  @override
  Future<Employee> deactivate(String id, {String? dol}) =>
      _withApiErrors(() async {
        return Employee.fromJson(
          _asJsonMap(
            await _api.postJson(
              '/employees/${Uri.encodeComponent(id)}/deactivate',
              data: dol == null ? null : {'dol': dol},
            ),
          ),
        );
      });

  @override
  Future<Employee> reactivate(String id) => _withApiErrors(() async {
    return Employee.fromJson(
      _asJsonMap(
        await _api.postJson(
          '/employees/${Uri.encodeComponent(id)}/reactivate',
        ),
      ),
    );
  });
}

Map<String, dynamic> _asJsonMap(Object? value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) return value.map((key, item) => MapEntry('$key', item));
  _invalidResponse();
}

Never _invalidResponse() => throw const AppException(
  code: 'INVALID_RESPONSE',
  message: 'The server returned an invalid employee response.',
  details: {},
);

Future<T> _withApiErrors<T>(Future<T> Function() request) async {
  try {
    return await request();
  } on DioException catch (error) {
    throw AppException.fromDioException(error);
  }
}
