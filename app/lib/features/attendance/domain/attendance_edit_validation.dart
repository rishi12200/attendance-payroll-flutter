String? validateAttendanceEdit({
  required String status,
  required DateTime? inTime,
  required DateTime? outTime,
  required String reason,
}) {
  if (reason.trim().isEmpty) return 'Enter a reason for this edit.';
  if (reason.trim().length > 200) {
    return 'Reason must be 200 characters or fewer.';
  }

  final timesAllowed = status == 'P' || status == 'H';
  if (!timesAllowed && (inTime != null || outTime != null)) {
    return 'Times are only allowed with Present or Half day.';
  }
  if (outTime != null && inTime == null) {
    return 'Select an in time before setting an out time.';
  }
  if (inTime != null && outTime != null) {
    final duration = outTime.difference(inTime);
    if (duration.isNegative || duration.inMicroseconds == 0) {
      return 'Out time must be after in time.';
    }
    if (duration > const Duration(hours: 24)) {
      return 'Out time must be within 24 hours of in time.';
    }
  }
  return null;
}
