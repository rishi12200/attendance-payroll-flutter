import 'package:dio/dio.dart';

import '../../../core/api/api_client.dart';
import '../../../core/api/app_exception.dart';
import '../domain/leave_request.dart';
import '../domain/leave_type.dart';

abstract interface class LeaveRepository {
  Future<LeaveRequest> apply({
    required String leaveTypeId,
    required String fromDate,
    required String toDate,
    required String reason,
    String session = 'full',
  });
  Future<List<LeaveType>> listLeaveTypes({String status = 'all'});
  Future<LeaveType> createLeaveType(Map<String, Object?> values);
  Future<LeaveType> updateLeaveType(String id, Map<String, Object?> changes);
  Future<LeaveType> deactivateLeaveType(String id);
  Future<LeaveType> reactivateLeaveType(String id);
  Future<LeaveBalance> getBalance({int? year, String? empId});
  Future<List<LeaveRequest>> myRequests(String status);
  Future<LeaveRequest> cancel(String id);
  Future<List<LeaveRequest>> adminList(String status, {String? empId});
  Future<LeaveRequest> get(String id);
  Future<LeaveRequest> decide({
    required String id,
    required String decision,
    String? note,
  });
}

class ApiLeaveRepository implements LeaveRepository {
  const ApiLeaveRepository(this._api);
  final ApiTransport _api;

  @override
  Future<LeaveRequest> apply({
    required String leaveTypeId,
    required String fromDate,
    required String toDate,
    required String reason,
    String session = 'full',
  }) => _withApiErrors(
    () async => LeaveRequest.fromJson(
      _asJsonMap(
        await _api.postJson(
          '/leaves',
          data: {
            'leaveTypeId': leaveTypeId,
            'fromDate': fromDate,
            'toDate': toDate,
            'reason': reason,
            if (session != 'full') 'session': session,
          },
        ),
      ),
    ),
  );

  @override
  Future<List<LeaveType>> listLeaveTypes({String status = 'all'}) =>
      _withApiErrors(
        () async => _asJsonList(
          await _api.getJson(
            '/leave-types',
            queryParameters: {'status': status},
          ),
        ).map(LeaveType.fromJson).toList(growable: false),
      );

  @override
  Future<LeaveType> createLeaveType(Map<String, Object?> values) =>
      _withApiErrors(
        () async => LeaveType.fromJson(
          _asJsonMap(await _api.postJson('/leave-types', data: values)),
        ),
      );

  @override
  Future<LeaveType> updateLeaveType(String id, Map<String, Object?> changes) =>
      _withApiErrors(
        () async => LeaveType.fromJson(
          _asJsonMap(
            await _api.patchJson(
              '/leave-types/${Uri.encodeComponent(id)}',
              data: changes,
            ),
          ),
        ),
      );

  @override
  Future<LeaveType> deactivateLeaveType(String id) =>
      _typeAction(id, 'deactivate');

  @override
  Future<LeaveType> reactivateLeaveType(String id) =>
      _typeAction(id, 'reactivate');

  Future<LeaveType> _typeAction(String id, String action) => _withApiErrors(
    () async => LeaveType.fromJson(
      _asJsonMap(
        await _api.postJson('/leave-types/${Uri.encodeComponent(id)}/$action'),
      ),
    ),
  );

  @override
  Future<LeaveBalance> getBalance({int? year, String? empId}) => _withApiErrors(
    () async => LeaveBalance.fromJson(
      _asJsonMap(
        await _api.getJson(
          '/leaves/balance',
          queryParameters: {'year': ?year, 'empId': ?empId},
        ),
      ),
    ),
  );

  @override
  Future<List<LeaveRequest>> myRequests(String status) => _withApiErrors(
    () async => _asJsonList(
      await _api.getJson('/leaves/me', queryParameters: {'status': status}),
    ).map(LeaveRequest.fromJson).toList(growable: false),
  );

  @override
  Future<LeaveRequest> cancel(String id) => _withApiErrors(
    () async => LeaveRequest.fromJson(
      _asJsonMap(
        await _api.postJson('/leaves/${Uri.encodeComponent(id)}/cancel'),
      ),
    ),
  );

  @override
  Future<List<LeaveRequest>> adminList(String status, {String? empId}) =>
      _withApiErrors(
        () async => _asJsonList(
          await _api.getJson(
            '/leaves',
            queryParameters: {'status': status, 'empId': ?empId},
          ),
        ).map(LeaveRequest.fromJson).toList(growable: false),
      );

  @override
  Future<LeaveRequest> get(String id) => _withApiErrors(
    () async => LeaveRequest.fromJson(
      _asJsonMap(await _api.getJson('/leaves/${Uri.encodeComponent(id)}')),
    ),
  );

  @override
  Future<LeaveRequest> decide({
    required String id,
    required String decision,
    String? note,
  }) => _withApiErrors(
    () async => LeaveRequest.fromJson(
      _asJsonMap(
        await _api.postJson(
          '/leaves/${Uri.encodeComponent(id)}/decision',
          data: {'decision': decision, 'note': ?note},
        ),
      ),
    ),
  );
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
