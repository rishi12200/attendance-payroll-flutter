import '../../branches/domain/branch.dart';
import 'attendance_views.dart';

String holidayWeekday(String date) {
  final parsed = _parseDate(date);
  const weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  return weekdays[parsed.weekday - 1];
}

String readableHolidayDate(String date) {
  final parsed = _parseDate(date);
  const weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  return '${weekdays[parsed.weekday - 1]}, ${parsed.day} '
      '${months[parsed.month - 1]} ${parsed.year}';
}

String adminHolidayScopeLabel(AttendanceHoliday holiday) {
  if (holiday.scope != 'branches') return 'All branches';
  final names = holiday.branchNames.toSet().toList()..sort();
  if (names.length <= 2) return names.join(', ');
  return '${names.take(2).join(', ')} +${names.length - 2} more';
}

String employeeHolidayScopeLabel(AttendanceHoliday holiday) =>
    holiday.scope == 'branches' ? 'Your branch' : 'All branches';

Map<String, List<String>> groupBranchesByState(Iterable<Branch> branches) {
  final displayNames = <String, String>{};
  final grouped = <String, List<String>>{};
  for (final branch in branches) {
    if (branch.status != BranchStatus.active) continue;
    final state = branch.state.trim();
    if (state.isEmpty) continue;
    final key = state.toLowerCase();
    displayNames.putIfAbsent(key, () => state);
    grouped.putIfAbsent(key, () => []).add(branch.id);
  }
  final keys = grouped.keys.toList()
    ..sort(
      (left, right) => displayNames[left]!.toLowerCase().compareTo(
        displayNames[right]!.toLowerCase(),
      ),
    );
  return Map<String, List<String>>.unmodifiable({
    for (final key in keys)
      displayNames[key]!: List<String>.unmodifiable(grouped[key]!..sort()),
  });
}

DateTime _parseDate(String date) {
  final parts = date.split('-');
  if (parts.length != 3) throw const FormatException('Expected YYYY-MM-DD.');
  final year = int.tryParse(parts[0]);
  final month = int.tryParse(parts[1]);
  final day = int.tryParse(parts[2]);
  if (year == null || month == null || day == null) {
    throw const FormatException('Expected YYYY-MM-DD.');
  }
  final parsed = DateTime.utc(year, month, day);
  if (parsed.year != year || parsed.month != month || parsed.day != day) {
    throw const FormatException('Expected a valid YYYY-MM-DD date.');
  }
  return parsed;
}
