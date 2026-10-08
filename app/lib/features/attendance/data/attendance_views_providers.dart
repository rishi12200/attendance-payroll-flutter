import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/auth_providers.dart';
import '../domain/attendance_views.dart';
import 'attendance_views_repository.dart';

final attendanceViewsRepositoryProvider = Provider<AttendanceViewsRepository>(
  (ref) => ApiAttendanceViewsRepository(ref.watch(apiClientProvider)),
);

final myAttendanceCalendarProvider =
    FutureProvider.family<AttendanceCalendar, String>(
      (ref, month) {
        ref.watch(signedInUidProvider);
        return ref
            .watch(attendanceViewsRepositoryProvider)
            .getMyCalendar(month);
      },
      retry: (_, _) => null,
    );

final employeeAttendanceCalendarProvider =
    FutureProvider.family<AttendanceCalendar, (String, String)>(
      (ref, arguments) {
        ref.watch(signedInUidProvider);
        return ref
            .watch(attendanceViewsRepositoryProvider)
            .getEmployeeCalendar(arguments.$1, arguments.$2);
      },
      retry: (_, _) => null,
    );

final attendanceSummaryProvider =
    FutureProvider.family<List<AttendanceMonthSummaryRow>, String>(
      (ref, month) {
        ref.watch(signedInUidProvider);
        return ref
            .watch(attendanceViewsRepositoryProvider)
            .getSummary(month);
      },
      retry: (_, _) => null,
    );

final attendanceByDateProvider =
    FutureProvider.family<AttendanceByDate, String>(
      (ref, date) {
        ref.watch(signedInUidProvider);
        return ref
            .watch(attendanceViewsRepositoryProvider)
            .getByDate(date);
      },
      retry: (_, _) => null,
    );

final attendanceHolidaysProvider =
    FutureProvider.family<List<AttendanceHoliday>, String>(
      (ref, year) {
        ref.watch(signedInUidProvider);
        return ref
            .watch(attendanceViewsRepositoryProvider)
            .listHolidays(year);
      },
      retry: (_, _) => null,
    );

final attendanceSettingsProvider =
    FutureProvider<AttendanceSettings>((ref) {
      ref.watch(signedInUidProvider);
      return ref.watch(attendanceViewsRepositoryProvider).getSettings();
    }, retry: (_, _) => null);

final flaggedCheckinsProvider = FutureProvider.family<List<FlaggedCheckin>, ({String? from, String? to})>(
  (ref, range) {
    ref.watch(signedInUidProvider);
    return ref.watch(attendanceViewsRepositoryProvider).getFlaggedCheckins(
      from: range.from,
      to: range.to,
    );
  },
  retry: (_, _) => null,
);
