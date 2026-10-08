import 'package:app/core/api/api_client.dart';
import 'package:app/core/api/app_exception.dart';
import 'package:app/features/attendance/data/attendance_repository.dart';
import 'package:app/features/attendance/domain/attendance.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

class _Request {
  const _Request(this.method, this.path, this.data, this.queryParameters);

  final String method;
  final String path;
  final Object? data;
  final Map<String, Object?>? queryParameters;
}

class _FakeApi implements ApiTransport {
  final requests = <_Request>[];
  Object? response;
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
    throw UnimplementedError();
  }

  @override
  Future<Object?> deleteJson(String path) async {
    throw UnimplementedError();
  }

  @override
  Future<Object?> postJson(String path, {Object? data}) async {
    requests.add(_Request('POST', path, data, null));
    if (error case final value?) throw value;
    return response;
  }
}

void main() {
  test('parses optional attendance day values when missing or null', () {
    final absent = AttendanceDay.fromJson({'status': 'P'});
    expect(absent.inTime, isNull);
    expect(absent.outTime, isNull);
    expect(absent.inDistance, isNull);
    expect(absent.workedMinutes, isNull);

    final nullable = AttendanceDay.fromJson({
      'status': 'P',
      'inTime': null,
      'outTime': null,
      'inBranchId': null,
      'outBranchId': null,
      'inDistance': null,
      'outDistance': null,
      'workedMinutes': null,
      'source': null,
    });
    expect(nullable.inBranchId, isNull);
    expect(nullable.source, isNull);
  });

  test('parses month attendance including an empty days map', () {
    final attendance = MonthAttendance.fromJson({
      'month': '2026-10',
      'today': '2026-10-07',
      'serverTime': '2026-10-07T12:00:00.000Z',
      'days': {},
    });
    expect(attendance.days, isEmpty);
    expect(
      MonthAttendance.fromJson({
        'month': '2026-10',
        'today': '2026-10-07',
        'serverTime': '2026-10-07T12:00:00.000Z',
        'days': {
          '2026-10-07': {
            'status': 'P',
            'inTime': '2026-10-07T09:00:00.000Z',
          },
        },
      }).days['2026-10-07']?.inTime,
      '2026-10-07T09:00:00.000Z',
    );
  });

  test('parses punch result values and optional checkout branch data', () {
    final checkin = CheckInResult.fromJson({
      'date': '2026-10-07',
      'status': 'P',
      'inTime': '2026-10-07T09:00:00.000Z',
      'branchId': 'branch-1',
      'branchName': 'Chennai',
      'distanceMeters': 40,
    });
    expect(checkin.distanceMeters, 40);
    expect(checkin.branchName, 'Chennai');

    final checkout = CheckOutResult.fromJson({
      'date': '2026-10-07',
      'inTime': '2026-10-07T09:00:00.000Z',
      'outTime': '2026-10-07T11:05:00.000Z',
      'workedMinutes': 125,
      'branchId': null,
      'branchName': null,
      'distanceMeters': null,
    });
    expect(checkout.workedMinutes, 125);
    expect(checkout.branchId, isNull);
    expect(checkout.distanceMeters, isNull);
  });

  test('uses backend endpoints and sends only the specified punch payload', () async {
    final api = _FakeApi();
    final repository = ApiAttendanceRepository(api);
    api.response = {
      'month': '2026-10',
      'today': '2026-10-07',
      'serverTime': '2026-10-07T12:00:00.000Z',
      'days': {},
    };
    await repository.getMyMonth('2026-10');

    const payload = {
      'lat': 13.08,
      'lng': 80.27,
      'accuracy': 8.0,
      'deviceId': 'install-id',
      'isMocked': false,
    };
    api.response = {
      'date': '2026-10-07',
      'status': 'P',
      'inTime': '2026-10-07T12:00:00.000Z',
      'branchId': 'branch-1',
      'branchName': 'Chennai',
      'distanceMeters': 40,
    };
    await repository.checkIn(payload);
    api.response = {
      'date': '2026-10-07',
      'inTime': '2026-10-07T12:00:00.000Z',
      'outTime': '2026-10-07T14:05:00.000Z',
      'workedMinutes': 125,
      'branchId': 'branch-1',
      'branchName': 'Chennai',
      'distanceMeters': 40,
    };
    await repository.checkOut(payload);

    expect(api.requests.map((request) => '${request.method} ${request.path}'), [
      'GET /attendance/me',
      'POST /attendance/check-in',
      'POST /attendance/check-out',
    ]);
    expect(api.requests.first.queryParameters, {'month': '2026-10'});
    expect(api.requests[1].data, payload);
    expect(api.requests[2].data, payload);
    expect((api.requests[1].data as Map).keys.toSet(), {
      'lat',
      'lng',
      'accuracy',
      'deviceId',
      'isMocked',
    });
  });

  test('maps backend attendance errors without logging request data', () async {
    final request = RequestOptions(path: '/attendance/check-in');
    final api = _FakeApi()
      ..error = DioException(
        requestOptions: request,
        response: Response(
          requestOptions: request,
          statusCode: 422,
          data: {
            'error': {
              'code': 'OUTSIDE_GEOFENCE',
              'message': 'You are outside.',
              'details': {'distanceMeters': 1200},
            },
          },
        ),
      );
    await expectLater(
      ApiAttendanceRepository(api).checkIn(const {}),
      throwsA(
        isA<AppException>()
            .having((error) => error.code, 'code', 'OUTSIDE_GEOFENCE')
            .having((error) => error.statusCode, 'statusCode', 422),
      ),
    );
  });
}
