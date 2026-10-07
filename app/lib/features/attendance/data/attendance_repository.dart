import 'package:dio/dio.dart';

import '../../../core/api/api_client.dart';
import '../../../core/api/app_exception.dart';
import '../domain/attendance.dart';

abstract interface class AttendanceRepository {
  Future<MonthAttendance> getMyMonth(String month);
  Future<CheckInResult> checkIn(Map<String, Object?> payload);
  Future<CheckOutResult> checkOut(Map<String, Object?> payload);
}

class ApiAttendanceRepository implements AttendanceRepository {
  const ApiAttendanceRepository(this._api);

  final ApiTransport _api;

  @override
  Future<MonthAttendance> getMyMonth(String month) => _withApiErrors(
    () async => MonthAttendance.fromJson(
      _asJsonMap(
        await _api.getJson(
          '/attendance/me',
          queryParameters: {'month': month},
        ),
      ),
    ),
  );

  @override
  Future<CheckInResult> checkIn(Map<String, Object?> payload) =>
      _withApiErrors(
        () async => CheckInResult.fromJson(
          _asJsonMap(
            await _api.postJson('/attendance/check-in', data: payload),
          ),
        ),
      );

  @override
  Future<CheckOutResult> checkOut(Map<String, Object?> payload) =>
      _withApiErrors(
        () async => CheckOutResult.fromJson(
          _asJsonMap(
            await _api.postJson('/attendance/check-out', data: payload),
          ),
        ),
      );
}

Map<String, dynamic> _asJsonMap(Object? value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) return value.map((key, item) => MapEntry('$key', item));
  throw const AppException(
    code: 'INVALID_RESPONSE',
    message: 'The server returned an invalid attendance response.',
    details: {},
  );
}

Future<T> _withApiErrors<T>(Future<T> Function() request) async {
  try {
    return await request();
  } on DioException catch (error) {
    throw AppException.fromDioException(error);
  }
}
