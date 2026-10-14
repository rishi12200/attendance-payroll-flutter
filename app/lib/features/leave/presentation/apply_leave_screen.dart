import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/api/app_exception.dart';
import '../../attendance/domain/attendance_controller.dart';
import '../data/leave_providers.dart';
import '../domain/leave_form_validation.dart';
import '../domain/leave_helpers.dart';
import '../domain/leave_type.dart';

class ApplyLeaveScreen extends ConsumerStatefulWidget {
  const ApplyLeaveScreen({super.key});
  @override
  ConsumerState<ApplyLeaveScreen> createState() => _ApplyLeaveScreenState();
}

class _ApplyLeaveScreenState extends ConsumerState<ApplyLeaveScreen> {
  final _formKey = GlobalKey<FormState>();
  final _reasonController = TextEditingController();
  String? _fromDate;
  String? _toDate;
  String? _serverToday;
  bool _loadingToday = false;
  bool _submitting = false;
  String? _leaveTypeId;
  String _session = 'full';

  @override
  void dispose() {
    _reasonController.dispose();
    super.dispose();
  }

  Future<String> _loadServerToday() async {
    setState(() => _loadingToday = true);
    await ref
        .read(attendanceControllerProvider.notifier)
        .refresh(allowWhileWorking: true);
    if (!mounted) throw StateError('Apply screen closed.');
    final state = ref.read(attendanceControllerProvider);
    final today = switch (state) {
      AttendanceNotCheckedIn(:final today) => today,
      AttendanceCheckedIn(:final today) => today,
      AttendanceCompleted(:final today) => today,
      AttendanceLoadError(:final error) => throw error,
      _ => throw StateError('Server attendance date is not available.'),
    };
    _serverToday = today;
    setState(() => _loadingToday = false);
    return today;
  }

  Future<void> _chooseDates() async {
    try {
      final today = await _loadServerToday();
      if (!mounted) return;
      final window = leavePickerWindow(today);
      final range = await showDateRangePicker(
        context: context,
        firstDate: window.start,
        lastDate: window.end,
        helpText: 'Choose leave dates',
      );
      if (range == null || !mounted) return;
      setState(() {
        _fromDate = _dateKey(range.start);
        _toDate = _dateKey(range.end);
        if (_fromDate != _toDate) _session = 'full';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _loadingToday = false);
      final message = error is AppException
          ? error.message
          : error is Exception
          ? error.toString().replaceFirst('Exception: ', '')
          : 'Could not load today from the server. Please try again.';
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
    }
  }

  Future<void> _submit() async {
    if (_leaveTypeId == null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Choose a leave type.')));
      return;
    }
    if (!_formKey.currentState!.validate() ||
        _fromDate == null ||
        _toDate == null) {
      if (_fromDate == null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Choose a date range first.')),
        );
      }
      return;
    }
    final validation = validateLeaveApplication(
      fromDate: _fromDate!,
      toDate: _toDate!,
      reason: _reasonController.text,
    );
    if (validation != null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(validation)));
      return;
    }
    setState(() => _submitting = true);
    try {
      await ref
          .read(leaveRepositoryProvider)
          .apply(
            leaveTypeId: _leaveTypeId!,
            fromDate: _fromDate!,
            toDate: _toDate!,
            reason: _reasonController.text.trim(),
            session: _session,
          );
      ref.invalidate(myLeaveRequestsProvider);
      ref.invalidate(leaveBalanceProvider);
      if (mounted) context.pop(true);
    } on AppException catch (error) {
      if (!mounted) return;
      final message = leaveErrorMessage(error);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not submit the leave request.')),
        );
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final types = ref.watch(leaveTypesProvider('active'));
    final balance = ref.watch(leaveBalanceProvider((year: null, empId: null)));
    final typeOptions = types.asData?.value ?? const <LeaveType>[];
    final noTypes = types.asData?.value.isEmpty == true;
    final selectedType = typeOptions
        .where((type) => type.id == _leaveTypeId)
        .firstOrNull;
    final balanceByType = {
      for (final item in balance.asData?.value.types ?? const [])
        item.leaveTypeId: item,
    };
    final canHalf =
        _fromDate != null &&
        _fromDate == _toDate &&
        selectedType?.allowHalfDay == true;
    if (!canHalf && _session != 'full') _session = 'full';
    final days = _fromDate == null || _toDate == null
        ? null
        : _session == 'full'
        ? leaveDayCount(_fromDate!, _toDate!).toDouble()
        : 0.5;
    return Scaffold(
      appBar: AppBar(title: const Text('Apply for leave')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            types.when(
              loading: () => const LinearProgressIndicator(),
              error: (error, _) => Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    error is AppException
                        ? error.message
                        : 'Could not load leave types.',
                  ),
                  TextButton(
                    onPressed: () =>
                        ref.invalidate(leaveTypesProvider('active')),
                    child: const Text('Retry'),
                  ),
                ],
              ),
              data: (items) => items.isEmpty
                  ? const Text('No leave types are available. Ask your admin.')
                  : DropdownButtonFormField<String>(
                      key: const ValueKey('leave-type-picker'),
                      initialValue: _leaveTypeId,
                      decoration: const InputDecoration(
                        labelText: 'Leave type',
                      ),
                      items: [
                        for (final type in items)
                          DropdownMenuItem(
                            value: type.id,
                            child: Text(
                              _typeOptionLabel(
                                type,
                                balanceByType[type.id]?.remaining,
                              ),
                            ),
                          ),
                      ],
                      onChanged: _submitting
                          ? null
                          : (value) => setState(() {
                              _leaveTypeId = value;
                              _session = 'full';
                            }),
                      validator: (value) =>
                          value == null ? 'Choose a leave type.' : null,
                    ),
            ),
            if (selectedType != null &&
                _fromDate != null &&
                _toDate != null) ...[
              const SizedBox(height: 12),
              if (canHalf)
                SegmentedButton<String>(
                  key: const ValueKey('leave-session-choice'),
                  segments: const [
                    ButtonSegment(value: 'full', label: Text('Full day')),
                    ButtonSegment(
                      value: 'first_half',
                      label: Text('First half'),
                    ),
                    ButtonSegment(
                      value: 'second_half',
                      label: Text('Second half'),
                    ),
                  ],
                  selected: {_session},
                  onSelectionChanged: (selection) =>
                      setState(() => _session = selection.single),
                )
              else if (_fromDate != _toDate)
                const Text('Half days are only for a single date.')
              else if (!selectedType.allowHalfDay)
                const Text("This leave type doesn't allow half days."),
            ],
            if (types.asData?.value.isEmpty == true) const SizedBox.shrink(),
            OutlinedButton.icon(
              key: const ValueKey('leave-date-range-button'),
              onPressed: _loadingToday || _submitting || noTypes
                  ? null
                  : _chooseDates,
              icon: _loadingToday
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.date_range),
              label: Text(
                _fromDate == null
                    ? 'Choose date range'
                    : readableLeaveRange(_fromDate!, _toDate!),
              ),
            ),
            if (_serverToday != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'First available date: ${_serverToday!}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            if (days != null) ...[
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text('${pluralDays(days)} selected'),
              ),
              if (days > 31)
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Text(
                    'A leave request cannot exceed 31 days.',
                    style: TextStyle(color: Colors.red),
                  ),
                ),
            ],
            const SizedBox(height: 20),
            TextFormField(
              key: const ValueKey('leave-reason-field'),
              controller: _reasonController,
              enabled: !_submitting && !noTypes,
              maxLength: 200,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Reason',
                alignLabelWithHint: true,
              ),
              validator: (value) => (value ?? '').trim().isEmpty
                  ? 'Enter a reason for your leave request.'
                  : null,
            ),
            const SizedBox(height: 8),
            const Text(
              'Weekly offs and holidays inside your range are not counted as leave. Days where you already have attendance are skipped.',
            ),
            const SizedBox(height: 24),
            FilledButton(
              key: const ValueKey('submit-leave-button'),
              onPressed: _submitting || typeOptions.isEmpty ? null : _submit,
              child: _submitting
                  ? const CircularProgressIndicator()
                  : const Text('Submit request'),
            ),
          ],
        ),
      ),
    );
  }
}

String _dateKey(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

String _typeOptionLabel(LeaveType type, double? remaining) => [
  type.name,
  type.code,
  paidLabel(type.paid),
  if (type.annualQuotaDays == null)
    'No limit'
  else if (remaining != null)
    '${pluralDays(remaining)} left',
].join(' · ');

String leaveErrorMessage(AppException error) {
  final details = error.details;
  final typeName = details['leaveTypeName'];
  final year = details['yearLabel'];
  final remaining = details['remaining'];
  final requested = details['requested'];
  return switch (error.code) {
    'QUOTA_EXCEEDED'
        when typeName is String &&
            year is String &&
            remaining is num &&
            requested is num =>
      'Not enough $typeName left for $year: ${pluralDays(remaining.toDouble())} left, you asked for ${formatDays(requested.toDouble())}.',
    'QUOTA_EXCEEDED' => error.message,
    'NO_WORKING_DAYS' => 'This range has no working days (weekly offs and holidays are not counted).',
    'NOT_A_WORKING_DAY' => 'Half-day leave must be requested on a working day.',
    'HALF_DAY_SINGLE_DATE' => 'A half-day request must cover exactly one date.',
    'HALF_DAY_NOT_ALLOWED' => "This leave type doesn't allow half days.",
    'LEAVE_TYPE_INACTIVE' =>
      'This leave type is no longer available. Choose another type.',
    'LEAVE_TYPE_MISSING' =>
      'This older request has no leave type and cannot be approved.',
    'LEAVE_OVERLAP' =>
      'You already have a leave request covering some of these dates.',
    'MONTH_LOCKED' =>
      'This month is locked, so leave cannot be requested for these dates.',
    'OUTSIDE_EMPLOYMENT_WINDOW' =>
      'Leave dates must fall within your employment dates.',
    'LEAVE_RANGE_TOO_LONG' => 'A leave request cannot exceed 31 days.',
    'INVALID_DATE_RANGE' => 'Choose a valid date range.',
    'LEAVE_TYPE_NOT_FOUND' =>
      'This leave type is no longer available. Choose another type.',
    _ => error.message,
  };
}
