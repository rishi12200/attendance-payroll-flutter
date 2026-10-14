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
  Future<Object?> patchJson(String path, {Object? data}) async {
    requests.add(_Request('PATCH', path, data, null));
    return response;
  }

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
        leaveTypeId: 'sick',
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
        'leaveTypeId': 'sick',
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

  test(
    'typed requests omit full session and never decide a paid type',
    () async {
      final api = _FakeApi()..response = _leave();
      final repository = ApiLeaveRepository(api);
      await repository.apply(
        leaveTypeId: 'sick',
        fromDate: '2026-10-12',
        toDate: '2026-10-12',
        reason: 'Visit',
      );
      expect(api.requests.single.data, {
        'leaveTypeId': 'sick',
        'fromDate': '2026-10-12',
        'toDate': '2026-10-12',
        'reason': 'Visit',
      });
      api.requests.clear();
      await repository.apply(
        leaveTypeId: 'sick',
        fromDate: '2026-10-12',
        toDate: '2026-10-12',
        reason: 'Visit',
        session: 'first_half',
      );
      expect((api.requests.single.data as Map)['session'], 'first_half');
      api.requests.clear();
      await repository.decide(id: 'x', decision: 'approved');
      expect(api.requests.single.data, {'decision': 'approved'});
    },
  );

  test('leave type endpoints, changed fields, and balance query', () async {
    final type = {
      'id': 'sick',
      'name': 'Sick Leave',
      'code': 'SL',
      'paid': true,
      'allowHalfDay': true,
    };
    final api = _FakeApi()..response = [type];
    final repository = ApiLeaveRepository(api);
    await repository.listLeaveTypes(status: 'active');
    expect(api.requests.last.path, '/leave-types');
    expect(api.requests.last.query, {'status': 'active'});
    api.response = type;
    await repository.createLeaveType({'name': 'Care', 'code': 'CARE'});
    await repository.updateLeaveType('sick', {'name': 'Medical Leave'});
    await repository.deactivateLeaveType('sick');
    await repository.reactivateLeaveType('sick');
    expect(api.requests[2].data, {'name': 'Medical Leave'});
    api.response = {
      'year': 2026,
      'label': '2026',
      'startDate': '2026-01-01',
      'endDate': '2026-12-31',
      'today': '2026-10-12',
      'types': [],
    };
    await repository.getBalance(year: 2026, empId: 'emp-1');
    expect(api.requests.last.path, '/leaves/balance');
    expect(api.requests.last.query, {'year': 2026, 'empId': 'emp-1'});
  });
}
