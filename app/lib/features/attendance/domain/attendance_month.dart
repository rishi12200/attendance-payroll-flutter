class AttendanceMonth {
  const AttendanceMonth._(this.year, this.month);

  final int year;
  final int month;

  factory AttendanceMonth.parse(String value) {
    final match = RegExp(r'^(\d{4})-(\d{2})$').firstMatch(value);
    final year = int.tryParse(match?.group(1) ?? '');
    final month = int.tryParse(match?.group(2) ?? '');
    if (year == null || month == null || year < 1 || month < 1 || month > 12) {
      throw const FormatException('Expected a month in YYYY-MM format.');
    }
    return AttendanceMonth._(year, month);
  }

  String get value =>
      '${year.toString().padLeft(4, '0')}-${month.toString().padLeft(2, '0')}';

  String get label {
    const names = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];
    return '${names[month - 1]} $year';
  }

  int get daysInMonth => DateTime.utc(year, month + 1, 0).day;

  int get mondayFirstWeekdayOffset => DateTime.utc(year, month, 1).weekday - 1;

  AttendanceMonth get previous {
    if (month == 1) return AttendanceMonth._(year - 1, 12);
    return AttendanceMonth._(year, month - 1);
  }

  AttendanceMonth get next {
    if (month == 12) return AttendanceMonth._(year + 1, 1);
    return AttendanceMonth._(year, month + 1);
  }

  int monthsUntil(AttendanceMonth other) =>
      (other.year - year) * 12 + other.month - month;

  bool canNavigateTo(AttendanceMonth target, {required AttendanceMonth today}) {
    final monthsBack = target.monthsUntil(this);
    return monthsBack >= 0 &&
        monthsBack <= 12 &&
        target.monthsUntil(today) >= 0;
  }
}

String previousMonth(String month) => AttendanceMonth.parse(month).previous.value;

String nextMonth(String month) => AttendanceMonth.parse(month).next.value;

String monthLabel(String month) => AttendanceMonth.parse(month).label;

int daysInMonth(String month) => AttendanceMonth.parse(month).daysInMonth;

int mondayFirstWeekdayOffset(String month) =>
    AttendanceMonth.parse(month).mondayFirstWeekdayOffset;
