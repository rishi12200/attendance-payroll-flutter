import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/auth_providers.dart';
import '../../../features/auth/domain/user_profile.dart';
import '../domain/attendance_views.dart';
import 'attendance_views_repository.dart';

final attendanceViewsRepositoryProvider = Provider<AttendanceViewsRepository>(
  (ref) => ApiAttendanceViewsRepository(ref.watch(apiClientProvider)),
);

final myAttendanceCalendarProvider =
    FutureProvider.family<AttendanceCalendar, String>((ref, month) {
      ref.watch(signedInUidProvider);
      return ref.watch(attendanceViewsRepositoryProvider).getMyCalendar(month);
    }, retry: (_, _) => null);

final employeeAttendanceCalendarProvider =
    FutureProvider.family<AttendanceCalendar, (String, String)>((
      ref,
      arguments,
    ) {
      ref.watch(signedInUidProvider);
      return ref
          .watch(attendanceViewsRepositoryProvider)
          .getEmployeeCalendar(arguments.$1, arguments.$2);
    }, retry: (_, _) => null);

final attendanceSummaryProvider =
    FutureProvider.family<List<AttendanceMonthSummaryRow>, String>((
      ref,
      month,
    ) {
      ref.watch(signedInUidProvider);
      return ref.watch(attendanceViewsRepositoryProvider).getSummary(month);
    }, retry: (_, _) => null);

final attendanceByDateProvider =
    FutureProvider.family<AttendanceByDate, String>((ref, date) {
      ref.watch(signedInUidProvider);
      return ref.watch(attendanceViewsRepositoryProvider).getByDate(date);
    }, retry: (_, _) => null);

final attendanceHolidaysProvider =
    FutureProvider.family<List<AttendanceHoliday>, String>((ref, year) {
      ref.watch(signedInUidProvider);
      return ref.watch(attendanceViewsRepositoryProvider).listHolidays(year);
    }, retry: (_, _) => null);

final adminAttendanceHolidaysProvider =
    FutureProvider.family<
      List<AttendanceHoliday>,
      ({String year, String? branchId})
    >((ref, query) {
      ref.watch(signedInUidProvider);
      return ref
          .watch(attendanceViewsRepositoryProvider)
          .listHolidays(query.year, branchId: query.branchId);
    }, retry: (_, _) => null);

final myHolidaysProvider =
    FutureProvider.family<List<AttendanceHoliday>, String>((ref, year) {
      ref.watch(signedInUidProvider);
      return ref.watch(attendanceViewsRepositoryProvider).myHolidays(year);
    }, retry: (_, _) => null);

final attendanceServerTodayProvider = FutureProvider<String>((ref) async {
  final profile = await ref.watch(currentProfileProvider.future);
  final repository = ref.watch(attendanceViewsRepositoryProvider);
  if (profile?.role == UserRole.admin) {
    return (await repository.getByDate('2000-01-01')).today;
  }
  return (await repository.getMyCalendar('2000-01')).today;
}, retry: (_, _) => null);

final attendanceSettingsProvider = FutureProvider<AttendanceSettings>((ref) {
  ref.watch(signedInUidProvider);
  return ref.watch(attendanceViewsRepositoryProvider).getSettings();
}, retry: (_, _) => null);

final flaggedCheckinsProvider =
    FutureProvider.family<List<FlaggedCheckin>, ({String? from, String? to})>((
      ref,
      range,
    ) {
      ref.watch(signedInUidProvider);
      return ref
          .watch(attendanceViewsRepositoryProvider)
          .getFlaggedCheckins(from: range.from, to: range.to);
    }, retry: (_, _) => null);
