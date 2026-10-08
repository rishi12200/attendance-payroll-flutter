import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/api/app_exception.dart';
import '../../attendance/domain/attendance_controller.dart';
import '../data/leave_providers.dart';
import '../domain/leave_form_validation.dart';
import '../domain/leave_helpers.dart';

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
            fromDate: _fromDate!,
            toDate: _toDate!,
            reason: _reasonController.text.trim(),
          );
      ref.invalidate(myLeaveRequestsProvider);
      if (mounted) context.pop(true);
    } on AppException catch (error) {
      if (!mounted) return;
      final message = switch (error.code) {
        'LEAVE_OVERLAP' =>
          'You already have a leave request covering some of these dates.',
        'MONTH_LOCKED' =>
          'This month is locked, so leave cannot be requested for these dates.',
        _ => error.message,
      };
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
    final days = _fromDate == null || _toDate == null
        ? null
        : leaveDayCount(_fromDate!, _toDate!);
    return Scaffold(
      appBar: AppBar(title: const Text('Apply for leave')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            OutlinedButton.icon(
              key: const ValueKey('leave-date-range-button'),
              onPressed: _loadingToday || _submitting ? null : _chooseDates,
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
                child: Text('$days ${days == 1 ? 'day' : 'days'} selected'),
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
              onPressed: _submitting ? null : _submit,
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
