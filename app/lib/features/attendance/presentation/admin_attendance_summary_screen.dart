import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/app_exception.dart';
import '../data/attendance_views_providers.dart';
import '../domain/attendance_helpers.dart';
import '../domain/attendance_month.dart';
import '../domain/attendance_views.dart';
import 'admin_attendance_day_screen.dart';

class AdminAttendanceSummaryScreen extends ConsumerStatefulWidget {
  const AdminAttendanceSummaryScreen({this.onOpenEmployee, super.key});

  final OpenEmployeeAttendance? onOpenEmployee;

  @override
  ConsumerState<AdminAttendanceSummaryScreen> createState() =>
      _AdminAttendanceSummaryScreenState();
}

class _AdminAttendanceSummaryScreenState
    extends ConsumerState<AdminAttendanceSummaryScreen> {
  late String _month;

  @override
  void initState() {
    super.initState();
    _month = istDateOf(DateTime.now().toUtc().toIso8601String())
        .substring(0, 7);
  }

  @override
  Widget build(BuildContext context) {
    final summaries = ref.watch(attendanceSummaryProvider(_month));
    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(attendanceSummaryProvider(_month));
        await ref.read(attendanceSummaryProvider(_month).future);
      },
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  monthLabel(_month),
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              OutlinedButton.icon(
                key: const ValueKey('attendance-summary-month-picker'),
                onPressed: () => _chooseMonth(context),
                icon: const Icon(Icons.calendar_month),
                label: const Text('Choose month'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          summaries.when(
            loading: () => const SizedBox(
              height: 220,
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (error, _) => _SummaryError(
              message: _errorMessage(error),
              onRetry: () => ref.invalidate(attendanceSummaryProvider(_month)),
            ),
            data: (rows) => _SummaryRows(
              rows: rows,
              month: _month,
              onOpenEmployee: widget.onOpenEmployee,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _chooseMonth(BuildContext context) async {
    final selected = await showDatePicker(
      context: context,
      initialDate: DateTime.parse('$_month-01T00:00:00Z'),
      firstDate: DateTime.utc(2000),
      lastDate: DateTime.utc(2100),
      helpText: 'Choose a date in the month to view',
    );
    if (selected == null || !mounted) return;
    final month =
        '${selected.year.toString().padLeft(4, '0')}-'
        '${selected.month.toString().padLeft(2, '0')}';
    setState(() => _month = month);
  }
}

class _SummaryRows extends StatelessWidget {
  const _SummaryRows({
    required this.rows,
    required this.month,
    required this.onOpenEmployee,
  });

  final List<AttendanceMonthSummaryRow> rows;
  final String month;
  final OpenEmployeeAttendance? onOpenEmployee;

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 36),
        child: Center(child: Text('No employee summaries for this month.')),
      );
    }
    return Column(
      children: [
        for (final row in rows)
          Card(
            child: ListTile(
              key: ValueKey('attendance-summary-${row.empId}'),
              onTap: onOpenEmployee == null
                  ? null
                  : () => onOpenEmployee!(row.empId, month),
              title: Text(row.name),
              subtitle: Text(
                '${row.empCode} · Present ${row.summary.present} · '
                'Half days ${row.summary.halfDays} · '
                'Absent ${row.summary.absent}',
              ),
              trailing: Text('LOP ${_summaryNumber(row.summary.lop)}'),
            ),
          ),
      ],
    );
  }
}

class _SummaryError extends StatelessWidget {
  const _SummaryError({required this.message, required this.onRetry});

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
  _ => 'Could not load attendance summaries. Please try again.',
};

String _summaryNumber(num value) =>
    value == value.roundToDouble() ? value.toInt().toString() : '$value';
