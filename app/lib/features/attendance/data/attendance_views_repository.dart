import 'package:dio/dio.dart';

import '../../../core/api/api_client.dart';
import '../../../core/api/app_exception.dart';
import '../domain/attendance_views.dart';

abstract interface class AttendanceViewsRepository {
  Future<AttendanceCalendar> getMyCalendar(String month);
  Future<AttendanceCalendar> getEmployeeCalendar(String empId, String month);
  Future<List<AttendanceMonthSummaryRow>> getSummary(String month);
  Future<AttendanceByDate> getByDate(String date);
  Future<AttendanceCalendarDay> editAttendance({
    required String empId,
    required String date,
    required String status,
    required String reason,
    String? inTime,
    String? outTime,
  });
  Future<List<AttendanceHoliday>> listHolidays(String year);
  Future<AttendanceHoliday> createHoliday({
    required String date,
    required String name,
  });
  Future<void> deleteHoliday(String date);
  Future<AttendanceSettings> getSettings();
  Future<AttendanceSettings> updateSettings(Map<String, Object?> changes);
  Future<List<FlaggedCheckin>> getFlaggedCheckins({String? from, String? to});
}

class ApiAttendanceViewsRepository implements AttendanceViewsRepository {
  const ApiAttendanceViewsRepository(this._api);

  final ApiTransport _api;

  @override
  Future<AttendanceCalendar> getMyCalendar(String month) =>
      _withApiErrors(() async {
        return AttendanceCalendar.fromJson(
          _asJsonMap(
            await _api.getJson(
              '/attendance/me/calendar',
              queryParameters: {'month': month},
            ),
          ),
        );
      });

  @override
  Future<AttendanceCalendar> getEmployeeCalendar(String empId, String month) =>
      _withApiErrors(() async {
        return AttendanceCalendar.fromJson(
          _asJsonMap(
            await _api.getJson(
              '/attendance/employee/${Uri.encodeComponent(empId)}/calendar',
              queryParameters: {'month': month},
            ),
          ),
        );
      });

  @override
  Future<List<AttendanceMonthSummaryRow>> getSummary(String month) =>
      _withApiErrors(() async {
        return _asJsonList(
          await _api.getJson(
            '/attendance/summary',
            queryParameters: {'month': month},
          ),
        ).map(AttendanceMonthSummaryRow.fromJson).toList(growable: false);
      });

  @override
  Future<AttendanceByDate> getByDate(String date) => _withApiErrors(() async {
    return AttendanceByDate.fromJson(
      _asJsonMap(
        await _api.getJson('/attendance', queryParameters: {'date': date}),
      ),
    );
  });

  @override
  Future<AttendanceCalendarDay> editAttendance({
    required String empId,
    required String date,
    required String status,
    required String reason,
    String? inTime,
    String? outTime,
  }) => _withApiErrors(() async {
    final body = <String, Object?>{
      'status': status,
      'inTime': ?inTime,
      'outTime': ?outTime,
      'reason': reason,
    };
    return AttendanceCalendarDay.fromJson(
      _asJsonMap(
        await _api.patchJson(
          '/attendance/${Uri.encodeComponent(empId)}/$date',
          data: body,
        ),
      ),
    );
  });

  @override
  Future<List<AttendanceHoliday>> listHolidays(String year) =>
      _withApiErrors(() async {
        return _asJsonList(
          await _api.getJson('/holidays', queryParameters: {'year': year}),
        ).map(AttendanceHoliday.fromJson).toList(growable: false);
      });

  @override
  Future<AttendanceHoliday> createHoliday({
    required String date,
    required String name,
  }) => _withApiErrors(() async {
    return AttendanceHoliday.fromJson(
      _asJsonMap(
        await _api.postJson('/holidays', data: {'date': date, 'name': name}),
      ),
    );
  });

  @override
  Future<void> deleteHoliday(String date) => _withApiErrors(() async {
    await _api.deleteJson('/holidays/$date');
  });

  @override
  Future<AttendanceSettings> getSettings() => _withApiErrors(() async {
    return AttendanceSettings.fromJson(
      _asJsonMap(await _api.getJson('/settings')),
    );
  });

  @override
  Future<AttendanceSettings> updateSettings(Map<String, Object?> changes) =>
      _withApiErrors(() async {
        return AttendanceSettings.fromJson(
          _asJsonMap(await _api.patchJson('/settings', data: changes)),
        );
      });

  @override
  Future<List<FlaggedCheckin>> getFlaggedCheckins({String? from, String? to}) =>
      _withApiErrors(() async {
        return _asJsonList(
          await _api.getJson(
            '/checkins/flagged',
            queryParameters: {'from': ?from, 'to': ?to},
          ),
        ).map(FlaggedCheckin.fromJson).toList(growable: false);
      });
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

List<Map<String, dynamic>> _asJsonList(Object? value) {
  if (value is! List) {
    throw const AppException(
      code: 'INVALID_RESPONSE',
      message: 'The server returned an invalid attendance response.',
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
