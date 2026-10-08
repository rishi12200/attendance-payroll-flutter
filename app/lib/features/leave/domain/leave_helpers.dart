int leaveDayCount(String fromDate, String toDate) {
  final from = _parseDate(fromDate);
  final to = _parseDate(toDate);
  if (to.isBefore(from)) return 0;
  return to.difference(from).inDays + 1;
}

String readableLeaveRange(String fromDate, String toDate) {
  final from = _parseDate(fromDate);
  final to = _parseDate(toDate);
  if (from == to) return _formatDate(from);
  if (from.year == to.year && from.month == to.month) {
    return '${from.day} - ${_formatDate(to)}';
  }
  if (from.year == to.year) {
    return '${from.day} ${_monthName(from.month)} - ${_formatDate(to)}';
  }
  return '${_formatDate(from)} - ${_formatDate(to)}';
}

String skippedReasonLabel(String reason) => switch (reason) {
  'weekly_off' => 'Sunday / weekly off',
  'holiday' => 'Holiday',
  'has_punch' => 'Already has attendance',
  'outside_employment' => 'Outside employment dates',
  _ => 'Skipped',
};

DateTime _parseDate(String value) {
  final parts = value.split('-');
  if (parts.length != 3) throw FormatException('Invalid leave date: $value');
  final year = int.tryParse(parts[0]);
  final month = int.tryParse(parts[1]);
  final day = int.tryParse(parts[2]);
  if (year == null || month == null || day == null) {
    throw FormatException('Invalid leave date: $value');
  }
  final date = DateTime.utc(year, month, day);
  if (date.year != year || date.month != month || date.day != day) {
    throw FormatException('Invalid leave date: $value');
  }
  return date;
}

String _formatDate(DateTime date) =>
    '${date.day} ${_monthName(date.month)} ${date.year}';

String _monthName(int month) => const [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
][month - 1];
