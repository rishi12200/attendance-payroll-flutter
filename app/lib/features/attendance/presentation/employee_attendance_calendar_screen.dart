import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/app_exception.dart';
import '../data/attendance_views_providers.dart';
import '../domain/attendance_helpers.dart';
import 'attendance_calendar_widget.dart';

class EmployeeAttendanceCalendarScreen extends ConsumerStatefulWidget {
  const EmployeeAttendanceCalendarScreen({super.key});

  @override
  ConsumerState<EmployeeAttendanceCalendarScreen> createState() =>
      _EmployeeAttendanceCalendarScreenState();
}

class _EmployeeAttendanceCalendarScreenState
    extends ConsumerState<EmployeeAttendanceCalendarScreen> {
  late String _month;

  @override
  void initState() {
    super.initState();
    final firstRequestDate = istDateOf(
      DateTime.now().toUtc().toIso8601String(),
    );
    _month = firstRequestDate.substring(0, 7);
  }

  @override
  Widget build(BuildContext context) {
    final attendance = ref.watch(myAttendanceCalendarProvider(_month));
    return Scaffold(
      appBar: AppBar(title: const Text('Attendance')),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(myAttendanceCalendarProvider(_month));
          await ref.read(myAttendanceCalendarProvider(_month).future);
        },
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            attendance.when(
              loading: () => const SizedBox(
                height: 240,
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (error, _) => _LoadError(
                message: _errorMessage(error),
                onRetry: () =>
                    ref.invalidate(myAttendanceCalendarProvider(_month)),
              ),
              data: (calendar) => AttendanceCalendarWidget(
                calendar: calendar,
                month: _month,
                onMonthChanged: (month) => setState(() => _month = month),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LoadError extends StatelessWidget {
  const _LoadError({required this.message, required this.onRetry});

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

String _errorMessage(Object error) => switch (error) {
  AppException(:final message) => message,
  _ => 'Could not load attendance. Please try again.',
};
