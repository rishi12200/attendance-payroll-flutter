import 'leave_helpers.dart';

import 'package:flutter/material.dart';

DateTimeRange leavePickerWindow(String serverToday) {
  final parts = serverToday.split('-').map(int.parse).toList();
  final first = DateTime(parts[0], parts[1], parts[2]);
  return DateTimeRange(start: first, end: first.add(const Duration(days: 365)));
}

String? validateLeaveApplication({
  required String fromDate,
  required String toDate,
  required String reason,
}) {
  if (reason.trim().isEmpty) return 'Enter a reason for your leave request.';
  if (reason.trim().length > 200) {
    return 'Reason must be 200 characters or fewer.';
  }
  final days = leaveDayCount(fromDate, toDate);
  if (days < 1) {
    return 'Choose a valid date range.';
  }
  if (days > 31) {
    return 'A leave request cannot exceed 31 days.';
  }
  return null;
}
