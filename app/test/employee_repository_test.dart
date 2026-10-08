import 'package:app/core/api/api_client.dart';
import 'package:app/core/api/app_exception.dart';
import 'package:app/features/employees/data/employee_repository.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

class RecordedRequest {
  const RecordedRequest(this.method, this.path, this.data, this.query);

  final String method;
  final String path;
  final Object? data;
  final Map<String, Object?>? query;
}

class FakeApiTransport implements ApiTransport {
  final List<RecordedRequest> requests = [];
  Object? response = employeeJson;
  Object? error;

  @override
  Future<Object?> getJson(
    String path, {
    Map<String, Object?>? queryParameters,
  }) async {
    requests.add(RecordedRequest('GET', path, null, queryParameters));
    if (error case final requestError?) throw requestError;
    return response;
  }

  @override
  Future<Object?> postJson(String path, {Object? data}) async {
    requests.add(RecordedRequest('POST', path, data, null));
    if (error case final requestError?) throw requestError;
    return response;
  }

  @override
  Future<Object?> patchJson(String path, {Object? data}) async {
    requests.add(RecordedRequest('PATCH', path, data, null));
    if (error case final requestError?) throw requestError;
    return response;
  }

  @override
  Future<Object?> deleteJson(String path) async {
    requests.add(RecordedRequest('DELETE', path, null, null));
    if (error case final requestError?) throw requestError;
    return response;
  }
}

const employeeJson = <String, Object?>{
  'uid': 'employee-1',
  'empCode': 'EMP001',
  'name': 'Employee One',
  'email': 'one@example.com',
  'role': 'employee',
  'status': 'active',
  'doj': '2026-10-01',
  'createdAt': '2026-10-01T00:00:00.000Z',
  'updatedAt': '2026-10-01T00:00:00.000Z',
  'primaryBranchId': null,
  'allowedBranchIds': <String>[],
};

void main() {
  test('lists employees using the requested status query', () async {
    final api = FakeApiTransport()..response = [employeeJson];
    final result = await ApiEmployeeRepository(api)
        .listEmployees(status: 'inactive');

    expect(result.single.uid, 'employee-1');
    expect(api.requests.single.method, 'GET');
    expect(api.requests.single.path, '/employees');
    expect(api.requests.single.query, {'status': 'inactive'});
  });

  test('uses the exact create body and omits empty optional fields', () async {
    final api = FakeApiTransport();
    await ApiEmployeeRepository(api).createEmployee(
      name: 'Employee One',
      email: 'one@example.com',
      tempPassword: 'temporary-password',
      doj: '2026-10-01',
      monthlyCtcPaise: 2500050,
      phone: '',
      primaryBranchId: 'branch-1',
      allowedBranchIds: ['branch-1'],
    );

    expect(api.requests.single.method, 'POST');
    expect(api.requests.single.path, '/employees');
    expect(api.requests.single.data, {
      'name': 'Employee One',
      'email': 'one@example.com',
      'tempPassword': 'temporary-password',
      'doj': '2026-10-01',
      'monthlyCtcPaise': 2500050,
      'primaryBranchId': 'branch-1',
      'allowedBranchIds': ['branch-1'],
    });
  });

  test('uses correct detail, salary, update and lifecycle endpoints', () async {
    final api = FakeApiTransport();
    final repository = ApiEmployeeRepository(api);
    await repository.getEmployee('employee-1');
    await repository.updateEmployee('employee-1', {
      'designation': 'Lead',
      'primaryBranchId': 'branch-1',
      'allowedBranchIds': ['branch-1', 'branch-2'],
    });
    api.response = [
      {
        'empId': 'employee-1',
        'effectiveFrom': '2026-10-01',
        'monthlyCtcPaise': 2500050,
      },
    ];
    await repository.listSalary('employee-1');
    api.response = {
      'empId': 'employee-1',
      'effectiveFrom': '2026-10-01',
      'monthlyCtcPaise': 2500050,
    };
    await repository.addSalaryRevision('employee-1', '2026-10-01', 2500050);
    api.response = employeeJson;
    await repository.deactivate('employee-1', dol: '2026-10-07');
    await repository.reactivate('employee-1');

    expect(api.requests.map((request) => '${request.method} ${request.path}'), [
      'GET /employees/employee-1',
      'PATCH /employees/employee-1',
      'GET /employees/employee-1/salary',
      'POST /employees/employee-1/salary',
      'POST /employees/employee-1/deactivate',
      'POST /employees/employee-1/reactivate',
    ]);
    expect(api.requests[3].data, {
      'effectiveFrom': '2026-10-01',
      'monthlyCtcPaise': 2500050,
    });
    expect(api.requests[1].data, {
      'designation': 'Lead',
      'primaryBranchId': 'branch-1',
      'allowedBranchIds': ['branch-1', 'branch-2'],
    });
    expect(api.requests[4].data, {'dol': '2026-10-07'});
    expect(api.requests[5].data, isNull);
  });

  test('maps backend Dio errors to AppException', () async {
    final request = RequestOptions(path: '/employees');
    final api = FakeApiTransport()
      ..error = DioException(
        requestOptions: request,
        response: Response(
          requestOptions: request,
          statusCode: 409,
          data: {
            'error': {
              'code': 'EMAIL_ALREADY_EXISTS',
              'message': 'An account already uses this email.',
              'details': {},
            },
          },
        ),
      );

    await expectLater(
      ApiEmployeeRepository(api).listEmployees(),
      throwsA(
        isA<AppException>()
            .having((error) => error.statusCode, 'statusCode', 409)
            .having((error) => error.code, 'code', 'EMAIL_ALREADY_EXISTS'),
      ),
    );
  });
}
