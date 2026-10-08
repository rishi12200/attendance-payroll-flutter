import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/app_exception.dart';
import '../data/attendance_views_providers.dart';
import '../domain/attendance_helpers.dart';
import '../domain/attendance_views.dart';

class AdminHolidaysScreen extends ConsumerStatefulWidget {
  const AdminHolidaysScreen({super.key});

  @override
  ConsumerState<AdminHolidaysScreen> createState() =>
      _AdminHolidaysScreenState();
}

class _AdminHolidaysScreenState extends ConsumerState<AdminHolidaysScreen> {
  late int _year;
  late DateTime _initialDate;

  @override
  void initState() {
    super.initState();
    _initialDate = _istTodayAsDateTime();
    _year = _initialDate.year;
  }

  @override
  Widget build(BuildContext context) {
    final holidays = ref.watch(attendanceHolidaysProvider('$_year'));
    return Scaffold(
      appBar: AppBar(
        title: const Text('Holidays'),
        actions: [
          IconButton(
            tooltip: 'Choose year',
            onPressed: () => _chooseYear(context),
            icon: Text('$_year'),
          ),
          IconButton(
            key: const ValueKey('add-holiday'),
            tooltip: 'Add holiday',
            onPressed: () => _addHoliday(context),
            icon: const Icon(Icons.add),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(attendanceHolidaysProvider('$_year'));
          await ref.read(attendanceHolidaysProvider('$_year').future);
        },
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            holidays.when(
              loading: () => const SizedBox(
                height: 220,
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (error, _) => _HolidayError(
                message: _errorMessage(error),
                onRetry: () =>
                    ref.invalidate(attendanceHolidaysProvider('$_year')),
              ),
              data: (items) {
                final sorted = [...items]
                  ..sort((a, b) => a.date.compareTo(b.date));
                if (sorted.isEmpty) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 36),
                    child: Center(child: Text('No holidays for this year.')),
                  );
                }
                return Column(
                  children: [
                    for (final holiday in sorted)
                      Card(
                        child: ListTile(
                          title: Text(holiday.name),
                          subtitle: Text(_formatDate(holiday.date)),
                          trailing: IconButton(
                            key: ValueKey('delete-holiday-${holiday.date}'),
                            tooltip: 'Delete ${holiday.name}',
                            onPressed: () => _confirmDelete(holiday),
                            icon: const Icon(Icons.delete_outline),
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _chooseYear(BuildContext context) async {
    final selected = await showDatePicker(
      context: context,
      initialDate: _initialDate.year == _year
          ? _initialDate
          : DateTime.utc(_year, 1, 1),
      firstDate: DateTime.utc(2000),
      lastDate: DateTime.utc(2100),
      helpText: 'Choose a date in the year',
    );
    if (selected == null || !mounted) return;
    setState(() => _year = selected.year);
  }

  Future<void> _addHoliday(BuildContext context) async {
    final created = await showDialog<AttendanceHoliday>(
      context: context,
      builder: (_) => _AddHolidayDialog(initialDate: _initialDate),
    );
    if (created == null || !mounted) return;
    setState(() => _year = int.parse(created.date.substring(0, 4)));
    _invalidateAttendanceViews(created.date);
    _showMessage('Holiday added.');
  }

  Future<void> _confirmDelete(AttendanceHoliday holiday) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete holiday?'),
        content: Text('Delete ${holiday.name} on ${_formatDate(holiday.date)}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const ValueKey('confirm-delete-holiday'),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ref
          .read(attendanceViewsRepositoryProvider)
          .deleteHoliday(holiday.date);
      if (!mounted) return;
      _invalidateAttendanceViews(holiday.date);
      _showMessage('Holiday deleted.');
    } on AppException catch (error) {
      if (mounted) _showMessage(error.message);
    }
  }

  void _invalidateAttendanceViews(String date) {
    ref.invalidate(attendanceHolidaysProvider(date.substring(0, 4)));
    ref.invalidate(myAttendanceCalendarProvider);
    ref.invalidate(employeeAttendanceCalendarProvider);
    ref.invalidate(attendanceSummaryProvider);
    ref.invalidate(attendanceByDateProvider);
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }
}

class _AddHolidayDialog extends ConsumerStatefulWidget {
  const _AddHolidayDialog({required this.initialDate});

  final DateTime initialDate;

  @override
  ConsumerState<_AddHolidayDialog> createState() => _AddHolidayDialogState();
}

class _AddHolidayDialogState extends ConsumerState<_AddHolidayDialog> {
  late final TextEditingController _nameController;
  late String _date;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController();
    _date = _dateString(widget.initialDate);
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Add holiday'),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        OutlinedButton.icon(
          key: const ValueKey('holiday-date-picker'),
          onPressed: _saving ? null : _chooseDate,
          icon: const Icon(Icons.calendar_month),
          label: Text(_formatDate(_date)),
        ),
        TextField(
          key: const ValueKey('holiday-name'),
          controller: _nameController,
          maxLength: 120,
          enabled: !_saving,
          decoration: const InputDecoration(labelText: 'Name'),
        ),
      ],
    ),
    actions: [
      TextButton(
        onPressed: _saving ? null : () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: _saving ? null : _save,
        child: _saving
            ? const SizedBox.square(
                dimension: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Text('Save'),
      ),
    ],
  );

  Future<void> _chooseDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.parse('${_date}T00:00:00Z'),
      firstDate: DateTime.utc(2000),
      lastDate: DateTime.utc(2100),
    );
    if (picked == null || !mounted) return;
    setState(() => _date = _dateString(picked));
  }

  Future<void> _save() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      _showMessage('Enter a holiday name.');
      return;
    }
    setState(() => _saving = true);
    try {
      final holiday = await ref
          .read(attendanceViewsRepositoryProvider)
          .createHoliday(date: _date, name: name);
      if (mounted) Navigator.pop(context, holiday);
    } on AppException catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      _showMessage(error.message);
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }
}

class _HolidayError extends StatelessWidget {
  const _HolidayError({required this.message, required this.onRetry});

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

DateTime _istTodayAsDateTime() {
  final date = istDateOf(DateTime.now().toUtc().toIso8601String());
  return DateTime.parse('${date}T00:00:00Z');
}

String _dateString(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-'
    '${date.month.toString().padLeft(2, '0')}-'
    '${date.day.toString().padLeft(2, '0')}';

String _formatDate(String date) =>
    formatIstDateLong('${date}T05:30:00.000Z');

String _errorMessage(Object error) => switch (error) {
  AppException(:final message) => message,
  _ => 'Could not load holidays. Please try again.',
};
