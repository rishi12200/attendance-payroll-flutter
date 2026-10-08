import 'package:flutter/material.dart';

import '../domain/attendance_helpers.dart';
import '../domain/attendance_month.dart';
import '../domain/attendance_views.dart';

typedef AttendanceCalendarEditCallback = Future<void> Function(
  AttendanceCalendarDay day,
);

class AttendanceCalendarWidget extends StatelessWidget {
  const AttendanceCalendarWidget({
    required this.calendar,
    required this.month,
    required this.onMonthChanged,
    this.onEdit,
    super.key,
  });

  final AttendanceCalendar calendar;
  final String month;
  final ValueChanged<String> onMonthChanged;
  final AttendanceCalendarEditCallback? onEdit;

  @override
  Widget build(BuildContext context) {
    final selected = AttendanceMonth.parse(month);
    final serverMonth = AttendanceMonth.parse(calendar.today.substring(0, 7));
    final previous = selected.previous;
    final next = selected.next;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SummaryHeader(summary: calendar.summary),
        const SizedBox(height: 12),
        Row(
          children: [
            IconButton(
              key: const ValueKey('previous-month'),
              tooltip: 'Previous month',
              onPressed: selected.canNavigateTo(previous, today: serverMonth)
                  ? () => onMonthChanged(previous.value)
                  : null,
              icon: const Icon(Icons.chevron_left),
            ),
            Expanded(
              child: Text(
                selected.label,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            IconButton(
              key: const ValueKey('next-month'),
              tooltip: 'Next month',
              onPressed: selected.canNavigateTo(next, today: serverMonth)
                  ? () => onMonthChanged(next.value)
                  : null,
              icon: const Icon(Icons.chevron_right),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            for (final day in ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'])
              Expanded(
                child: Center(
                  child: Text(
                    day,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        _CalendarGrid(
          calendar: calendar,
          month: selected,
          onTap: (day) => _showDayDetails(context, day),
        ),
        const SizedBox(height: 12),
        const _CalendarLegend(),
      ],
    );
  }

  Future<void> _showDayDetails(
    BuildContext context,
    AttendanceCalendarDay day,
  ) async {
    final canEdit =
        onEdit != null &&
        day.date.compareTo(calendar.today) <= 0 &&
        day.status != 'NOT_JOINED' &&
        day.status != 'LEFT';
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) =>
          _DayDetailsSheet(day: day, canEdit: canEdit, onEdit: onEdit),
    );
  }
}

class _SummaryHeader extends StatelessWidget {
  const _SummaryHeader({required this.summary});

  final AttendanceSummary summary;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 8,
    runSpacing: 4,
    children: [
      _SummaryChip('Present', summary.present),
      _SummaryChip('Half days', summary.halfDays),
      _SummaryChip('Absent', summary.absent),
      _SummaryChip('Paid leave', summary.paidLeave),
      _SummaryChip('Unpaid leave', summary.unpaidLeave),
      _SummaryChip('LOP days', summary.lop),
      _SummaryChip('Payable days', summary.payableDays),
    ],
  );
}

class _SummaryChip extends StatelessWidget {
  const _SummaryChip(this.label, this.value);

  final String label;
  final num value;

  @override
  Widget build(BuildContext context) => Chip(
    label: Text('$label: ${_summaryNumber(value)}'),
    visualDensity: VisualDensity.compact,
  );
}

String _summaryNumber(num value) =>
    value == value.roundToDouble() ? value.toInt().toString() : '$value';

class _CalendarGrid extends StatelessWidget {
  const _CalendarGrid({
    required this.calendar,
    required this.month,
    required this.onTap,
  });

  final AttendanceCalendar calendar;
  final AttendanceMonth month;
  final ValueChanged<AttendanceCalendarDay> onTap;

  @override
  Widget build(BuildContext context) {
    final offset = month.mondayFirstWeekdayOffset;
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: offset + month.daysInMonth,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 7,
        childAspectRatio: 0.78,
        crossAxisSpacing: 3,
        mainAxisSpacing: 3,
      ),
      itemBuilder: (context, index) {
        if (index < offset) return const SizedBox.shrink();
        final dateNumber = index - offset + 1;
        final date = '${month.value}-${dateNumber.toString().padLeft(2, '0')}';
        final day = calendar.days.firstWhere(
          (entry) => entry.date == date,
          orElse: () => AttendanceCalendarDay(
            date: date,
            weekday:
                DateTime.utc(month.year, month.month, dateNumber).weekday % 7,
            status: 'PENDING',
            derived: false,
          ),
        );
        final code = _statusCode(day.status);
        final color = _statusColor(context, day.status);
        final isToday = day.date == calendar.today;
        return Semantics(
          label: '$date, ${_statusWord(day.status)}',
          button: true,
          child: InkWell(
            key: ValueKey('calendar-day-$date'),
            borderRadius: BorderRadius.circular(8),
            onTap: () => onTap(day),
            child: Container(
              key: ValueKey('calendar-status-$date'),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: isToday
                      ? Theme.of(context).colorScheme.primary
                      : color,
                  width: isToday ? 2 : 1,
                ),
              ),
              padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 1),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text('$dateNumber'),
                  Text(
                    code,
                    maxLines: 1,
                    style: TextStyle(
                      color: color,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

String _statusCode(String status) => switch (status) {
  'P' => 'P',
  'H' => 'H',
  'A' => 'A',
  'L' => 'L',
  'UL' => 'UL',
  'WEEKLY_OFF' => 'WO',
  'HOLIDAY' => 'HOL',
  'NOT_JOINED' || 'LEFT' || 'PENDING' => '-',
  _ => '-',
};

String _statusWord(String status) => switch (status) {
  'P' => 'Present',
  'H' => 'Half day',
  'A' => 'Absent',
  'L' => 'Paid leave',
  'UL' => 'Unpaid leave',
  'WEEKLY_OFF' => 'Weekly off',
  'HOLIDAY' => 'Holiday',
  'NOT_JOINED' => 'Not joined',
  'LEFT' => 'Left',
  'PENDING' => 'Pending',
  _ => status,
};

Color _statusColor(BuildContext context, String status) {
  final scheme = Theme.of(context).colorScheme;
  return switch (status) {
    'P' => Colors.green.shade800,
    'H' => Colors.teal.shade800,
    'A' => scheme.error,
    'L' => Colors.blue.shade800,
    'UL' => Colors.deepOrange.shade800,
    'WEEKLY_OFF' => scheme.secondary,
    'HOLIDAY' => Colors.purple.shade800,
    _ => scheme.outline,
  };
}

class _CalendarLegend extends StatelessWidget {
  const _CalendarLegend();

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 12,
    runSpacing: 6,
    children: const [
      _LegendItem(code: 'P', label: 'Present'),
      _LegendItem(code: 'H', label: 'Half day'),
      _LegendItem(code: 'A', label: 'Absent'),
      _LegendItem(code: 'L', label: 'Paid leave'),
      _LegendItem(code: 'UL', label: 'Unpaid leave'),
      _LegendItem(code: 'WO', label: 'Weekly off'),
      _LegendItem(code: 'HOL', label: 'Holiday'),
      _LegendItem(code: '-', label: 'Not joined / left / pending'),
    ],
  );
}

class _LegendItem extends StatelessWidget {
  const _LegendItem({required this.code, required this.label});

  final String code;
  final String label;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(code, style: const TextStyle(fontWeight: FontWeight.bold)),
      const SizedBox(width: 4),
      Text(label),
    ],
  );
}

class _DayDetailsSheet extends StatelessWidget {
  const _DayDetailsSheet({
    required this.day,
    required this.canEdit,
    required this.onEdit,
  });

  final AttendanceCalendarDay day;
  final bool canEdit;
  final AttendanceCalendarEditCallback? onEdit;

  @override
  Widget build(BuildContext context) => SafeArea(
    child: Padding(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              formatIstDateLong('${day.date}T00:00:00Z'),
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              'Status: ${_statusWord(day.status)} (${_statusCode(day.status)})',
            ),
            if (day.derived) const Text('No attendance recorded'),
            if (day.holidayName != null) Text('Holiday: ${day.holidayName}'),
            if (day.inTime != null) Text('In: ${formatIstTime(day.inTime!)}'),
            if (day.outTime != null)
              Text('Out: ${formatIstTime(day.outTime!)}'),
            if (day.workedMinutes != null)
              Text('Worked: ${formatWorkedMinutes(day.workedMinutes!)}'),
            if (day.inBranchName != null)
              Text('In branch: ${day.inBranchName}'),
            if (day.outBranchName != null)
              Text('Out branch: ${day.outBranchName}'),
            if (day.source != null)
              Text(
                'Source: ${day.source == 'admin_edit' ? 'Admin edit' : 'App'}',
              ),
            if (day.editedBy != null) Text('Edited by: ${day.editedBy}'),
            if (day.editedAt != null)
              Text(
                'Edited at: ${formatIstDateLong(day.editedAt!)} '
                '${formatIstTime(day.editedAt!)}',
              ),
            if (canEdit)
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton.icon(
                  onPressed: () {
                    Navigator.of(context).pop();
                    onEdit!(day);
                  },
                  icon: const Icon(Icons.edit),
                  label: const Text('Edit'),
                ),
              ),
          ],
        ),
      ),
    ),
  );
}
