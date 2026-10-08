import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/app_exception.dart';
import '../data/attendance_views_providers.dart';
import '../domain/attendance_edit_validation.dart';
import '../domain/attendance_helpers.dart';
import '../domain/attendance_views.dart';

Future<void> showAdminAttendanceEditSheet({
  required BuildContext context,
  required String empId,
  required String serverToday,
  required AttendanceCalendarDay day,
  required VoidCallback onSaved,
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  builder: (context) => AdminAttendanceEditSheet(
    empId: empId,
    serverToday: serverToday,
    day: day,
    onSaved: onSaved,
  ),
);

class AdminAttendanceEditSheet extends ConsumerStatefulWidget {
  const AdminAttendanceEditSheet({
    required this.empId,
    required this.serverToday,
    required this.day,
    required this.onSaved,
    super.key,
  });

  final String empId;
  final String serverToday;
  final AttendanceCalendarDay day;
  final VoidCallback onSaved;

  @override
  ConsumerState<AdminAttendanceEditSheet> createState() =>
      _AdminAttendanceEditSheetState();
}

class _AdminAttendanceEditSheetState
    extends ConsumerState<AdminAttendanceEditSheet> {
  static const _statuses = {
    'P': 'Present',
    'H': 'Half day',
    'A': 'Absent',
    'L': 'Paid leave',
    'UL': 'Unpaid leave',
  };

  late String _status;
  late final TextEditingController _reasonController;
  TimeOfDay? _inTime;
  TimeOfDay? _outTime;
  bool _saving = false;

  bool get _timesAllowed => _status == 'P' || _status == 'H';

  @override
  void initState() {
    super.initState();
    _status = _statuses.containsKey(widget.day.status)
        ? widget.day.status
        : 'P';
    _reasonController = TextEditingController();
    _inTime = _timeOfDay(widget.day.inTime);
    _outTime = _timeOfDay(widget.day.outTime);
  }

  @override
  void dispose() {
    _reasonController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(20, 4, 20, 20 + bottomInset),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Edit attendance · ${widget.day.date}',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                key: const ValueKey('attendance-edit-status'),
                initialValue: _status,
                decoration: const InputDecoration(labelText: 'Status'),
                items: [
                  for (final entry in _statuses.entries)
                    DropdownMenuItem(
                      value: entry.key,
                      child: Text(entry.value),
                    ),
                ],
                onChanged: _saving
                    ? null
                    : (status) {
                        if (status == null) return;
                        setState(() {
                          _status = status;
                          if (status != 'P' && status != 'H') {
                            _inTime = null;
                            _outTime = null;
                          }
                        });
                      },
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      key: const ValueKey('pick-in-time'),
                      onPressed: !_timesAllowed || _saving
                          ? null
                          : () => _chooseTime(isInTime: true),
                      child: Text('In time: ${_formatTimeOfDay(_inTime)}'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton(
                      key: const ValueKey('pick-out-time'),
                      onPressed: !_timesAllowed || _saving
                          ? null
                          : () => _chooseTime(isInTime: false),
                      child: Text('Out time: ${_formatTimeOfDay(_outTime)}'),
                    ),
                  ),
                ],
              ),
              TextField(
                key: const ValueKey('attendance-edit-reason'),
                controller: _reasonController,
                maxLength: 200,
                enabled: !_saving,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(labelText: 'Reason'),
              ),
              const SizedBox(height: 12),
              FilledButton(
                key: const ValueKey('save-attendance-edit'),
                onPressed: _saving ? null : _save,
                child: _saving
                    ? const SizedBox.square(
                        dimension: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Save'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _chooseTime({required bool isInTime}) async {
    final initial = isInTime ? _inTime : _outTime;
    final selected = await showTimePicker(
      context: context,
      initialTime: initial ?? const TimeOfDay(hour: 9, minute: 0),
    );
    if (selected == null || !mounted) return;
    setState(() {
      if (isInTime) {
        _inTime = selected;
      } else {
        _outTime = selected;
      }
    });
  }

  Future<void> _save() async {
    final validation = validateAttendanceEdit(
      status: _status,
      inTime: _inTime == null
          ? null
          : DateTime.parse(istToUtcIso(widget.day.date, _inTime!)),
      outTime: _outTime == null
          ? null
          : DateTime.parse(istToUtcIso(widget.day.date, _outTime!)),
      reason: _reasonController.text,
    );
    if (validation != null) {
      _showMessage(validation);
      return;
    }

    setState(() => _saving = true);
    try {
      await ref
          .read(attendanceViewsRepositoryProvider)
          .editAttendance(
            empId: widget.empId,
            date: widget.day.date,
            status: _status,
            inTime: _timesAllowed && _inTime != null
                ? istToUtcIso(widget.day.date, _inTime!)
                : null,
            outTime: _timesAllowed && _outTime != null
                ? istToUtcIso(widget.day.date, _outTime!)
                : null,
            reason: _reasonController.text.trim(),
          );
      if (!mounted) return;
      widget.onSaved();
      Navigator.of(context).pop();
    } on AppException catch (error) {
      if (mounted) _showMessage(error.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }
}

TimeOfDay? _timeOfDay(String? isoUtc) {
  if (isoUtc == null) return null;
  final ist = DateTime.parse(isoUtc)
      .toUtc()
      .add(const Duration(hours: 5, minutes: 30));
  return TimeOfDay(hour: ist.hour, minute: ist.minute);
}

String _formatTimeOfDay(TimeOfDay? time) {
  if (time == null) return 'Not set';
  final hour = time.hour % 12 == 0 ? 12 : time.hour % 12;
  final suffix = time.hour < 12 ? 'AM' : 'PM';
  return '${hour.toString().padLeft(2, '0')}:'
      '${time.minute.toString().padLeft(2, '0')} $suffix';
}
