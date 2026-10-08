import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/api/app_exception.dart';
import '../data/attendance_views_providers.dart';
import '../domain/attendance_helpers.dart';
import '../domain/attendance_views.dart';
import 'admin_attendance_summary_screen.dart';

typedef OpenEmployeeAttendance = void Function(String empId, String month);

class AdminAttendanceScreen extends StatefulWidget {
  const AdminAttendanceScreen({super.key});

  @override
  State<AdminAttendanceScreen> createState() => _AdminAttendanceScreenState();
}

class _AdminAttendanceScreenState extends State<AdminAttendanceScreen> {
  int _view = 0;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Attendance')),
    body: Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: SegmentedButton<int>(
            segments: const [
              ButtonSegment(value: 0, label: Text('Day')),
              ButtonSegment(value: 1, label: Text('Month summary')),
            ],
            selected: {_view},
            onSelectionChanged: (selection) =>
                setState(() => _view = selection.first),
          ),
        ),
        Expanded(
          child: _view == 0
              ? AdminAttendanceDayScreen(
                  onOpenEmployee: (id, month) => context.go(
                    '/admin/attendance/employee/${Uri.encodeComponent(id)}?month=$month',
                  ),
                )
              : AdminAttendanceSummaryScreen(
                  onOpenEmployee: (id, month) => context.go(
                    '/admin/attendance/employee/${Uri.encodeComponent(id)}?month=$month',
                  ),
                ),
        ),
      ],
    ),
  );
}

class AdminAttendanceDayScreen extends ConsumerStatefulWidget {
  const AdminAttendanceDayScreen({this.onOpenEmployee, super.key});

  final OpenEmployeeAttendance? onOpenEmployee;

  @override
  ConsumerState<AdminAttendanceDayScreen> createState() =>
      _AdminAttendanceDayScreenState();
}

class _AdminAttendanceDayScreenState
    extends ConsumerState<AdminAttendanceDayScreen> {
  late String _date;

  @override
  void initState() {
    super.initState();
    _date = istDateOf(DateTime.now().toUtc().toIso8601String());
  }

  @override
  Widget build(BuildContext context) {
    final attendance = ref.watch(attendanceByDateProvider(_date));
    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(attendanceByDateProvider(_date));
        await ref.read(attendanceByDateProvider(_date).future);
      },
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  attendance.asData?.value.today == _date
                      ? 'Today'
                      : 'Day view',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              OutlinedButton.icon(
                key: const ValueKey('attendance-date-picker'),
                onPressed: () => _chooseDate(context),
                icon: const Icon(Icons.calendar_month),
                label: Text(formatIstDateLong('${_date}T00:00:00Z')),
              ),
            ],
          ),
          const SizedBox(height: 12),
          attendance.when(
            loading: () => const SizedBox(
              height: 220,
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (error, _) => _DayViewError(
              message: _errorMessage(error),
              onRetry: () => ref.invalidate(attendanceByDateProvider(_date)),
            ),
            data: (data) => _AttendanceRows(
              attendance: data,
              onOpenEmployee: widget.onOpenEmployee,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _chooseDate(BuildContext context) async {
    final date = DateTime.parse('${_date}T00:00:00Z');
    final selected = await showDatePicker(
      context: context,
      initialDate: date,
      firstDate: DateTime.utc(2000),
      lastDate: DateTime.utc(2100),
    );
    if (selected == null || !mounted) return;
    setState(() {
      _date =
          '${selected.year.toString().padLeft(4, '0')}-'
          '${selected.month.toString().padLeft(2, '0')}-'
          '${selected.day.toString().padLeft(2, '0')}';
    });
  }
}

class _AttendanceRows extends StatelessWidget {
  const _AttendanceRows({
    required this.attendance,
    required this.onOpenEmployee,
  });

  final AttendanceByDate attendance;
  final OpenEmployeeAttendance? onOpenEmployee;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Wrap(
        spacing: 8,
        runSpacing: 4,
        children: [
          for (final status in const [
            'P',
            'H',
            'A',
            'L',
            'UL',
            'WEEKLY_OFF',
            'HOLIDAY',
            'PENDING',
          ])
            Chip(
              label: Text(
                '${_statusName(status)}: ${attendance.totals[status] ?? 0}',
              ),
              visualDensity: VisualDensity.compact,
            ),
        ],
      ),
      const SizedBox(height: 8),
      if (attendance.rows.isEmpty)
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 36),
          child: Center(child: Text('No employees scheduled for this date.')),
        )
      else
        for (final row in attendance.rows)
          Card(
            child: ListTile(
              key: ValueKey('attendance-row-${row.empId}'),
              onTap: onOpenEmployee == null
                  ? null
                  : () => onOpenEmployee!(
                      row.empId,
                      attendance.date.substring(0, 7),
                    ),
              title: Text(row.name),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${row.empCode} · ${_statusName(row.status)}'),
                  if (row.inTime != null)
                    Text('In: ${formatIstTime(row.inTime!)}'),
                  if (row.outTime != null)
                    Text('Out: ${formatIstTime(row.outTime!)}'),
                  if (row.workedMinutes != null)
                    Text('Worked: ${formatWorkedMinutes(row.workedMinutes!)}'),
                  if (row.inBranchName != null)
                    Text('In branch: ${row.inBranchName}'),
                  if (row.outBranchName != null)
                    Text('Out branch: ${row.outBranchName}'),
                  if (row.noCheckout)
                    const Text(
                      'No check-out',
                      key: ValueKey('no-checkout-marker'),
                    ),
                  if (row.checkedInNow)
                    const Text(
                      'Checked in now',
                      key: ValueKey('checked-in-now-marker'),
                    ),
                ],
              ),
              trailing: const Icon(Icons.chevron_right),
            ),
          ),
    ],
  );
}

class _DayViewError extends StatelessWidget {
  const _DayViewError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 36),
    child: Column(
      children: [
        Text(message, textAlign: TextAlign.center),
        const SizedBox(height: 12),
        OutlinedButton(onPressed: onRetry, child: const Text('Retry')),
      ],
    ),
  );
}

String _errorMessage(Object error) => switch (error) {
  AppException(:final message) => message,
  _ => 'Could not load attendance. Please try again.',
};

String _statusName(String status) => switch (status) {
  'P' => 'Present',
  'H' => 'Half day',
  'A' => 'Absent',
  'L' => 'Paid leave',
  'UL' => 'Unpaid leave',
  'WEEKLY_OFF' => 'Weekly off',
  'HOLIDAY' => 'Holiday',
  'NOT_JOINED' => 'Not joined',
  'LEFT' => 'Left',
  _ => status == 'PENDING' ? 'Pending' : status,
};
