import 'package:dio/dio.dart';

import '../../../core/api/api_client.dart';
import '../../../core/api/app_exception.dart';
import '../domain/leave_request.dart';

abstract interface class LeaveRepository {
  Future<LeaveRequest> apply({
    required String fromDate,
    required String toDate,
    required String reason,
  });
  Future<List<LeaveRequest>> myRequests(String status);
  Future<LeaveRequest> cancel(String id);
  Future<List<LeaveRequest>> adminList(String status, {String? empId});
  Future<LeaveRequest> get(String id);
  Future<LeaveRequest> decide({
    required String id,
    required String decision,
    String? leaveType,
    String? note,
  });
}

class ApiLeaveRepository implements LeaveRepository {
  const ApiLeaveRepository(this._api);
  final ApiTransport _api;

  @override
  Future<LeaveRequest> apply({
    required String fromDate,
    required String toDate,
    required String reason,
  }) => _withApiErrors(() async => LeaveRequest.fromJson(_asJsonMap(
    await _api.postJson('/leaves', data: {
      'fromDate': fromDate,
      'toDate': toDate,
      'reason': reason,
    }),
  )));

  @override
  Future<List<LeaveRequest>> myRequests(String status) =>
      _withApiErrors(() async => _asJsonList(await _api.getJson(
        '/leaves/me', queryParameters: {'status': status},
      )).map(LeaveRequest.fromJson).toList(growable: false));

  @override
  Future<LeaveRequest> cancel(String id) => _withApiErrors(() async =>
      LeaveRequest.fromJson(_asJsonMap(await _api.postJson(
        '/leaves/${Uri.encodeComponent(id)}/cancel',
      ))));

  @override
  Future<List<LeaveRequest>> adminList(String status, {String? empId}) =>
      _withApiErrors(() async => _asJsonList(await _api.getJson(
        '/leaves', queryParameters: {'status': status, 'empId': ?empId},
      )).map(LeaveRequest.fromJson).toList(growable: false));

  @override
  Future<LeaveRequest> get(String id) => _withApiErrors(() async =>
      LeaveRequest.fromJson(_asJsonMap(await _api.getJson(
        '/leaves/${Uri.encodeComponent(id)}',
      ))));

  @override
  Future<LeaveRequest> decide({
    required String id,
    required String decision,
    String? leaveType,
    String? note,
  }) => _withApiErrors(() async => LeaveRequest.fromJson(_asJsonMap(
    await _api.postJson(
      '/leaves/${Uri.encodeComponent(id)}/decision',
      data: {
        'decision': decision,
        'leaveType': ?leaveType,
        'note': ?note,
      },
    ),
  )));
}

Map<String, dynamic> _asJsonMap(Object? value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) return value.map((key, item) => MapEntry('$key', item));
  throw const AppException(
    code: 'INVALID_RESPONSE',
    message: 'The server returned an invalid leave response.',
    details: {},
  );
}

List<Map<String, dynamic>> _asJsonList(Object? value) {
  if (value is! List) {
    throw const AppException(
      code: 'INVALID_RESPONSE',
      message: 'The server returned an invalid leave response.',
      details: {},
    );
  }
  return value.map(_asJsonMap).toList(growable: false);
}

Future<T> _withApiErrors<T>(Future<T> Function() request) async {
  try {
    return await request();
  } on DioException catch (error) {
    throw AppException.fromDioException(error);
  }
}
