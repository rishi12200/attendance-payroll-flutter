import 'package:app/core/api/api_client.dart';
import 'package:app/features/leave/data/leave_repository.dart';
import 'package:flutter_test/flutter_test.dart';

class _Request {
  const _Request(this.method, this.path, this.data, this.query);
  final String method;
  final String path;
  final Object? data;
  final Map<String, Object?>? query;
}

class _FakeApi implements ApiTransport {
  final requests = <_Request>[];
  Object? response;
  @override
  Future<Object?> getJson(
    String path, {
    Map<String, Object?>? queryParameters,
  }) async {
    requests.add(_Request('GET', path, null, queryParameters));
    return response;
  }

  @override
  Future<Object?> postJson(String path, {Object? data}) async {
    requests.add(_Request('POST', path, data, null));
    return response;
  }

  @override
  Future<Object?> patchJson(String path, {Object? data}) async => null;
  @override
  Future<Object?> deleteJson(String path) async => null;
}

Map<String, Object?> _leave({bool adminFields = false}) => {
  'id': 'leave 1',
  'empId': 'emp-1',
  'fromDate': '2026-10-12',
  'toDate': '2026-10-14',
  'reason': 'Family event',
  'status': 'pending',
  'createdAt': '2026-10-08T10:00:00.000Z',
  'updatedAt': '2026-10-08T10:00:00.000Z',
  if (adminFields) 'empCode': 'EMP001',
  if (adminFields) 'name': 'Asha',
  if (adminFields) 'designation': 'Associate',
};

void main() {
  test(
    'uses leave endpoints and expected request bodies and filters',
    () async {
      final api = _FakeApi()..response = _leave();
      final repository = ApiLeaveRepository(api);
      await repository.apply(
        fromDate: '2026-10-12',
        toDate: '2026-10-14',
        reason: 'Family event',
      );
      api.response = [_leave()];
      await repository.myRequests('approved');
      api.response = _leave();
      await repository.cancel('leave 1');
      api.response = [_leave(adminFields: true)];
      final rows = await repository.adminList('pending', empId: 'emp-1');
      expect(rows.single.name, 'Asha');
      api.response = _leave();
      await repository.get('leave 1');
      api.response = _leave();
      await repository.decide(
        id: 'leave 1',
        decision: 'rejected',
        note: 'Coverage',
      );

      expect(api.requests.map((r) => '${r.method} ${r.path}'), [
        'POST /leaves',
        'GET /leaves/me',
        'POST /leaves/leave%201/cancel',
        'GET /leaves',
        'GET /leaves/leave%201',
        'POST /leaves/leave%201/decision',
      ]);
      expect(api.requests.first.data, {
        'fromDate': '2026-10-12',
        'toDate': '2026-10-14',
        'reason': 'Family event',
      });
      expect(api.requests[1].query, {'status': 'approved'});
      expect(api.requests[3].query, {'status': 'pending', 'empId': 'emp-1'});
      expect(api.requests.last.data, {
        'decision': 'rejected',
        'note': 'Coverage',
      });
    },
  );
}
