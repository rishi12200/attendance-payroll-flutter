import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/attendance_views_providers.dart';
import '../domain/attendance_helpers.dart';
import '../domain/attendance_views.dart';
import 'admin_attendance_edit_sheet.dart';
import 'attendance_calendar_widget.dart';

class AdminEmployeeAttendanceCalendarScreen extends ConsumerStatefulWidget {
  const AdminEmployeeAttendanceCalendarScreen({
    required this.empId,
    this.employeeName,
    this.initialMonth,
    super.key,
  });

  final String empId;
  final String? employeeName;
  final String? initialMonth;

  @override
  ConsumerState<AdminEmployeeAttendanceCalendarScreen> createState() =>
      _AdminEmployeeAttendanceCalendarScreenState();
}

class _AdminEmployeeAttendanceCalendarScreenState
    extends ConsumerState<AdminEmployeeAttendanceCalendarScreen> {
  late String _month;

  @override
  void initState() {
    super.initState();
    _month =
        widget.initialMonth ??
        istDateOf(DateTime.now().toUtc().toIso8601String()).substring(0, 7);
  }

  @override
  Widget build(BuildContext context) {
    final key = (widget.empId, _month);
    final attendance = ref.watch(employeeAttendanceCalendarProvider(key));
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.employeeName ?? 'Employee attendance'),
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(employeeAttendanceCalendarProvider(key));
          await ref.read(employeeAttendanceCalendarProvider(key).future);
        },
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            attendance.when(
              loading: () => const SizedBox(
                height: 240,
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (error, _) => _CalendarError(
                message: error.toString(),
                onRetry: () =>
                    ref.invalidate(employeeAttendanceCalendarProvider(key)),
              ),
              data: (calendar) => AttendanceCalendarWidget(
                calendar: calendar,
                month: _month,
                onMonthChanged: (month) => setState(() => _month = month),
                onEdit: (day) => _openEditSheet(day, calendar),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openEditSheet(
    AttendanceCalendarDay day,
    AttendanceCalendar calendar,
  ) => showAdminAttendanceEditSheet(
    context: context,
    empId: widget.empId,
    serverToday: calendar.today,
    day: day,
    onSaved: () {
      ref.invalidate(employeeAttendanceCalendarProvider((widget.empId, _month)));
      ref.invalidate(attendanceByDateProvider(day.date));
    },
  );
}

class _CalendarError extends StatelessWidget {
  const _CalendarError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 48),
    child: Column(
      children: [
        Text(message, textAlign: TextAlign.center),
        const SizedBox(height: 12),
        OutlinedButton(onPressed: onRetry, child: const Text('Retry')),
      ],
    ),
  );
}
