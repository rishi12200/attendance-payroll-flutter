import 'package:app/core/api/api_client.dart';
import 'package:app/core/api/app_exception.dart';
import 'package:app/features/branches/data/branch_repository.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

const branchJson = <String, Object?>{
  'id': 'branch-1',
  'name': 'Chennai Office',
  'address': '',
  'state': 'Tamil Nadu',
  'lat': 13.08,
  'lng': 80.27,
  'radiusMeters': 150,
  'status': 'active',
  'createdAt': '2026-10-07T00:00:00.000Z',
  'updatedAt': '2026-10-07T00:00:00.000Z',
};

class _Request {
  const _Request(this.method, this.path, this.data, this.query);
  final String method;
  final String path;
  final Object? data;
  final Map<String, Object?>? query;
}

class _FakeApi implements ApiTransport {
  final requests = <_Request>[];
  Object? response = branchJson;
  Object? error;

  @override
  Future<Object?> getJson(
    String path, {
    Map<String, Object?>? queryParameters,
  }) async {
    requests.add(_Request('GET', path, null, queryParameters));
    if (error case final value?) throw value;
    return response;
  }

  @override
  Future<Object?> patchJson(String path, {Object? data}) async {
    requests.add(_Request('PATCH', path, data, null));
    if (error case final value?) throw value;
    return response;
  }

  @override
  Future<Object?> postJson(String path, {Object? data}) async {
    requests.add(_Request('POST', path, data, null));
    if (error case final value?) throw value;
    return response;
  }
}

void main() {
  test('uses exact branch paths, methods, bodies and status query', () async {
    final api = _FakeApi();
    final repository = ApiBranchRepository(api);
    api.response = [branchJson];
    await repository.listBranches(status: 'inactive');
    api.response = branchJson;
    await repository.getBranch('branch 1');
    await repository.createBranch({'name': 'Office'});
    await repository.updateBranch('branch-1', {'radiusMeters': 300});
    await repository.deactivate('branch-1');
    await repository.reactivate('branch-1');

    expect(api.requests.map((item) => '${item.method} ${item.path}'), [
      'GET /branches',
      'GET /branches/branch%201',
      'POST /branches',
      'PATCH /branches/branch-1',
      'POST /branches/branch-1/deactivate',
      'POST /branches/branch-1/reactivate',
    ]);
    expect(api.requests.first.query, {'status': 'inactive'});
    expect(api.requests[2].data, {'name': 'Office'});
    expect(api.requests[3].data, {'radiusMeters': 300});
  });

  test('maps backend conflict errors to AppException', () async {
    final request = RequestOptions(path: '/branches');
    final api = _FakeApi()
      ..error = DioException(
        requestOptions: request,
        response: Response(
          requestOptions: request,
          statusCode: 409,
          data: {
            'error': {
              'code': 'BRANCH_NAME_EXISTS',
              'message': 'An active branch already uses this name.',
              'details': {},
            },
          },
        ),
      );
    await expectLater(
      ApiBranchRepository(api).createBranch({'name': 'Duplicate'}),
      throwsA(
        isA<AppException>()
            .having((error) => error.statusCode, 'statusCode', 409)
            .having((error) => error.code, 'code', 'BRANCH_NAME_EXISTS'),
      ),
    );
  });
}
