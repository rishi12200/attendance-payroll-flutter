import 'package:app/core/api/api_client.dart';
import 'package:app/features/attendance/data/attendance_views_repository.dart';
import 'package:app/features/attendance/domain/attendance_views.dart';
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
  Future<Object?> deleteJson(String path) async {
    requests.add(_Request('DELETE', path, null, null));
    return response;
  }
}

const _summary = {
  'daysInMonth': 31,
  'weeklyOffs': 4,
  'holidays': 0,
  'present': 1,
  'halfDays': 0,
  'absent': 0,
  'paidLeave': 0,
  'unpaidLeave': 0,
  'notJoinedOrLeftDays': 0,
  'pending': 26,
  'lop': 0,
  'payableDays': 31,
};

Map<String, Object?> _calendar() => {
  'month': '2026-10',
  'today': '2026-10-08',
  'serverTime': '2026-10-08T07:19:12.000Z',
  'summary': _summary,
  'days': [
    {
      'date': '2026-10-08',
      'weekday': 4,
      'status': 'PENDING',
      'derived': false,
    },
  ],
};

void main() {
  test('calls the exact attendance view endpoints and request shapes', () async {
    final api = _FakeApi();
    final repository = ApiAttendanceViewsRepository(api);

    api.response = _calendar();
    await repository.getMyCalendar('2026-10');
    await repository.getEmployeeCalendar('employee 1', '2026-10');

    api.response = [
      {
        'empId': 'employee-1',
        'empCode': 'EMP001',
        'name': 'Asha',
        'summary': _summary,
      },
    ];
    await repository.getSummary('2026-10');

    api.response = {
      'date': '2026-10-08',
      'today': '2026-10-08',
      'totals': {'P': 1},
      'rows': [],
    };
    await repository.getByDate('2026-10-08');

    api.response = {
      'date': '2026-10-08',
      'weekday': 4,
      'status': 'P',
      'derived': false,
    };
    await repository.editAttendance(
      empId: 'employee-1',
      date: '2026-10-08',
      status: 'P',
      inTime: '2026-10-08T03:30:00.000Z',
      reason: 'Corrected attendance',
    );

    api.response = [
      {'date': '2026-10-08', 'name': 'Founders day'},
    ];
    await repository.listHolidays('2026');
    api.response = {'date': '2026-10-08', 'name': 'Founders day'};
    await repository.createHoliday(date: '2026-10-08', name: 'Founders day');
    await repository.deleteHoliday('2026-10-08');

    api.response = {
      'companyName': '',
      'weeklyOffDays': [0],
      'perDayBasis': 'calendar',
      'maxAccuracyMeters': 100,
      'rejectMockLocation': true,
      'enforceCheckoutLocation': false,
    };
    await repository.getSettings();
    await repository.updateSettings({'weeklyOffDays': [0, 6]});

    api.response = [];
    await repository.getFlaggedCheckins(
      from: '2026-10-01',
      to: '2026-10-08',
    );

    expect(
      api.requests.map((request) => '${request.method} ${request.path}'),
      [
        'GET /attendance/me/calendar',
        'GET /attendance/employee/employee%201/calendar',
        'GET /attendance/summary',
        'GET /attendance',
        'PATCH /attendance/employee-1/2026-10-08',
        'GET /holidays',
        'POST /holidays',
        'DELETE /holidays/2026-10-08',
        'GET /settings',
        'PATCH /settings',
        'GET /checkins/flagged',
      ],
    );
    expect(api.requests[0].query, {'month': '2026-10'});
    expect(api.requests[1].query, {'month': '2026-10'});
    expect(api.requests[2].query, {'month': '2026-10'});
    expect(api.requests[3].query, {'date': '2026-10-08'});
    expect(api.requests[4].data, {
      'status': 'P',
      'inTime': '2026-10-08T03:30:00.000Z',
      'reason': 'Corrected attendance',
    });
    expect(api.requests[5].query, {'year': '2026'});
    expect(api.requests[6].data, {
      'date': '2026-10-08',
      'name': 'Founders day',
    });
    expect(api.requests[9].data, {'weeklyOffDays': [0, 6]});
    expect(api.requests[10].query, {
      'from': '2026-10-01',
      'to': '2026-10-08',
    });
  });

  test('parses endpoint response models', () async {
    final api = _FakeApi()..response = _calendar();
    final repository = ApiAttendanceViewsRepository(api);
    expect(await repository.getMyCalendar('2026-10'), isA<AttendanceCalendar>());

    api.response = [
      {
        'date': '2026-10-08',
        'name': 'Founders day',
      },
    ];
    expect(await repository.listHolidays('2026'), isA<List<AttendanceHoliday>>());
  });
}
