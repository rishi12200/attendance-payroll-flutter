import 'attendance.dart';

class AttendanceSummary {
  const AttendanceSummary({
    required this.daysInMonth,
    required this.weeklyOffs,
    required this.holidays,
    required this.present,
    required this.halfDays,
    required this.absent,
    required this.paidLeave,
    required this.unpaidLeave,
    required this.notJoinedOrLeftDays,
    required this.pending,
    required this.lop,
    required this.payableDays,
  });

  final int daysInMonth;
  final int weeklyOffs;
  final int holidays;
  final double present;
  final int halfDays;
  final double absent;
  final double paidLeave;
  final double unpaidLeave;
  final int notJoinedOrLeftDays;
  final double pending;
  final double lop;
  final double payableDays;

  factory AttendanceSummary.fromJson(Map<String, dynamic> json) =>
      AttendanceSummary(
        daysInMonth: _requiredInt(json, 'daysInMonth'),
        weeklyOffs: _requiredInt(json, 'weeklyOffs'),
        holidays: _requiredInt(json, 'holidays'),
        present: _requiredDouble(json, 'present'),
        halfDays: _requiredInt(json, 'halfDays'),
        absent: _requiredDouble(json, 'absent'),
        paidLeave: _requiredDouble(json, 'paidLeave'),
        unpaidLeave: _requiredDouble(json, 'unpaidLeave'),
        notJoinedOrLeftDays: _requiredInt(json, 'notJoinedOrLeftDays'),
        pending: _requiredDouble(json, 'pending'),
        lop: _requiredDouble(json, 'lop'),
        payableDays: _requiredDouble(json, 'payableDays'),
      );
}

class AttendanceCalendarDay {
  const AttendanceCalendarDay({
    required this.date,
    required this.weekday,
    required this.status,
    required this.derived,
    this.holidayName,
    this.inTime,
    this.outTime,
    this.workedMinutes,
    this.inBranchName,
    this.outBranchName,
    this.source,
    this.editedBy,
    this.editedAt,
    this.leaveTypeId,
    this.leaveTypeName,
    this.halfLeave,
    this.otherHalf,
  });

  final String date;
  final int weekday;
  final String status;
  final bool derived;
  final String? holidayName;
  final String? inTime;
  final String? outTime;
  final int? workedMinutes;
  final String? inBranchName;
  final String? outBranchName;
  final String? source;
  final String? editedBy;
  final String? editedAt;
  final String? leaveTypeId;
  final String? leaveTypeName;
  final HalfLeave? halfLeave;
  final String? otherHalf;

  factory AttendanceCalendarDay.fromJson(Map<String, dynamic> json) =>
      AttendanceCalendarDay(
        date: _requiredString(json, 'date'),
        weekday: _requiredInt(json, 'weekday'),
        status: _optionalString(json, 'status') ?? 'UNKNOWN',
        derived: _requiredBool(json, 'derived'),
        holidayName: _optionalString(json, 'holidayName'),
        inTime: _optionalString(json, 'inTime'),
        outTime: _optionalString(json, 'outTime'),
        workedMinutes: _optionalInt(json, 'workedMinutes'),
        inBranchName: _optionalString(json, 'inBranchName'),
        outBranchName: _optionalString(json, 'outBranchName'),
        source: _optionalString(json, 'source'),
        editedBy: _optionalString(json, 'editedBy'),
        editedAt: _optionalString(json, 'editedAt'),
        leaveTypeId: _optionalString(json, 'leaveTypeId'),
        leaveTypeName: _optionalString(json, 'leaveTypeName'),
        halfLeave: json['halfLeave'] is Map
            ? HalfLeave.fromJson(_asMap(json['halfLeave']))
            : null,
        otherHalf: _optionalString(json, 'otherHalf'),
      );
}

class AttendanceCalendar {
  const AttendanceCalendar({
    required this.month,
    required this.today,
    required this.serverTime,
    required this.summary,
    required this.days,
  });

  final String month;
  final String today;
  final String serverTime;
  final AttendanceSummary summary;
  final List<AttendanceCalendarDay> days;

  factory AttendanceCalendar.fromJson(Map<String, dynamic> json) {
    final rawDays = json['days'];
    if (rawDays is! List) {
      throw const FormatException(
        'The server returned an invalid attendance calendar.',
      );
    }
    return AttendanceCalendar(
      month: _requiredString(json, 'month'),
      today: _requiredString(json, 'today'),
      serverTime: _requiredString(json, 'serverTime'),
      summary: AttendanceSummary.fromJson(_requiredMap(json, 'summary')),
      days: List.unmodifiable(
        rawDays.map((item) => AttendanceCalendarDay.fromJson(_asMap(item))),
      ),
    );
  }
}

class AttendanceDateRow {
  const AttendanceDateRow({
    required this.empId,
    required this.empCode,
    required this.name,
    required this.status,
    required this.derived,
    required this.noCheckout,
    required this.checkedInNow,
    this.designation,
    this.inTime,
    this.outTime,
    this.workedMinutes,
    this.inBranchName,
    this.outBranchName,
    this.source,
    this.leaveTypeId,
    this.leaveTypeName,
    this.halfLeave,
    this.otherHalf,
  });

  final String empId;
  final String empCode;
  final String name;
  final String status;
  final bool derived;
  final bool noCheckout;
  final bool checkedInNow;
  final String? designation;
  final String? inTime;
  final String? outTime;
  final int? workedMinutes;
  final String? inBranchName;
  final String? outBranchName;
  final String? source;
  final String? leaveTypeId;
  final String? leaveTypeName;
  final HalfLeave? halfLeave;
  final String? otherHalf;

  factory AttendanceDateRow.fromJson(Map<String, dynamic> json) =>
      AttendanceDateRow(
        empId: _requiredString(json, 'empId'),
        empCode: _requiredString(json, 'empCode'),
        name: _requiredString(json, 'name'),
        status: _optionalString(json, 'status') ?? 'UNKNOWN',
        derived: _requiredBool(json, 'derived'),
        noCheckout: _requiredBool(json, 'noCheckout'),
        checkedInNow: _requiredBool(json, 'checkedInNow'),
        designation: _optionalString(json, 'designation'),
        inTime: _optionalString(json, 'inTime'),
        outTime: _optionalString(json, 'outTime'),
        workedMinutes: _optionalInt(json, 'workedMinutes'),
        inBranchName: _optionalString(json, 'inBranchName'),
        outBranchName: _optionalString(json, 'outBranchName'),
        source: _optionalString(json, 'source'),
        leaveTypeId: _optionalString(json, 'leaveTypeId'),
        leaveTypeName: _optionalString(json, 'leaveTypeName'),
        halfLeave: json['halfLeave'] is Map
            ? HalfLeave.fromJson(_asMap(json['halfLeave']))
            : null,
        otherHalf: _optionalString(json, 'otherHalf'),
      );
}

class AttendanceByDate {
  const AttendanceByDate({
    required this.date,
    required this.today,
    required this.totals,
    required this.rows,
  });

  final String date;
  final String today;
  final Map<String, int> totals;
  final List<AttendanceDateRow> rows;

  factory AttendanceByDate.fromJson(Map<String, dynamic> json) {
    final rawTotals = _requiredMap(json, 'totals');
    final totals = <String, int>{
      for (final entry in rawTotals.entries)
        entry.key: _asInt(entry.value, entry.key),
    };
    final rawRows = json['rows'];
    if (rawRows is! List) {
      throw const FormatException(
        'The server returned invalid attendance rows.',
      );
    }
    return AttendanceByDate(
      date: _requiredString(json, 'date'),
      today: _requiredString(json, 'today'),
      totals: Map.unmodifiable(totals),
      rows: List.unmodifiable(
        rawRows.map((item) => AttendanceDateRow.fromJson(_asMap(item))),
      ),
    );
  }
}

class AttendanceMonthSummaryRow {
  const AttendanceMonthSummaryRow({
    required this.empId,
    required this.empCode,
    required this.name,
    required this.summary,
  });

  final String empId;
  final String empCode;
  final String name;
  final AttendanceSummary summary;

  factory AttendanceMonthSummaryRow.fromJson(Map<String, dynamic> json) =>
      AttendanceMonthSummaryRow(
        empId: _requiredString(json, 'empId'),
        empCode: _requiredString(json, 'empCode'),
        name: _requiredString(json, 'name'),
        summary: AttendanceSummary.fromJson(_requiredMap(json, 'summary')),
      );
}

class AttendanceHoliday {
  const AttendanceHoliday({
    required this.id,
    required this.date,
    required this.name,
    this.scope = 'all',
    this.branchIds = const [],
    this.branchNames = const [],
    this.createdBy,
    this.createdAt,
  });

  final String id;
  final String date;
  final String name;
  final String scope;
  final List<String> branchIds;
  final List<String> branchNames;
  final String? createdBy;
  final String? createdAt;

  factory AttendanceHoliday.fromJson(Map<String, dynamic> json) {
    final date = _requiredString(json, 'date');
    final rawScope = json['scope'];
    final scope = rawScope == null
        ? 'all'
        : rawScope is String && (rawScope == 'all' || rawScope == 'branches')
        ? rawScope
        : throw const FormatException(
            'The server returned an invalid holiday scope.',
          );
    return AttendanceHoliday(
      id: json['id'] is String ? json['id'] as String : date,
      date: date,
      name: _requiredString(json, 'name'),
      scope: scope,
      branchIds: _optionalStringList(json['branchIds']),
      branchNames: _optionalStringList(json['branchNames']),
      createdBy: _optionalHolidayString(json['createdBy']),
      createdAt: _optionalHolidayString(json['createdAt']),
    );
  }
}

class AttendanceSettings {
  const AttendanceSettings({
    required this.companyName,
    required this.weeklyOffDays,
    required this.perDayBasis,
    required this.maxAccuracyMeters,
    required this.rejectMockLocation,
    required this.enforceCheckoutLocation,
    this.leaveYearStartMonth = 1,
  });

  final String companyName;
  final List<int> weeklyOffDays;
  final String perDayBasis;
  final int maxAccuracyMeters;
  final bool rejectMockLocation;
  final bool enforceCheckoutLocation;
  final int leaveYearStartMonth;

  factory AttendanceSettings.fromJson(Map<String, dynamic> json) {
    final rawWeekdays = json['weeklyOffDays'];
    if (rawWeekdays is! List || rawWeekdays.any((day) => day is! int)) {
      throw const FormatException(
        'The server returned invalid attendance settings.',
      );
    }
    return AttendanceSettings(
      companyName: _requiredString(json, 'companyName'),
      weeklyOffDays: List.unmodifiable(rawWeekdays.cast<int>()),
      perDayBasis: _requiredString(json, 'perDayBasis'),
      maxAccuracyMeters: _requiredInt(json, 'maxAccuracyMeters'),
      rejectMockLocation: _requiredBool(json, 'rejectMockLocation'),
      enforceCheckoutLocation: _requiredBool(json, 'enforceCheckoutLocation'),
      leaveYearStartMonth:
          json['leaveYearStartMonth'] is int &&
              (json['leaveYearStartMonth'] as int) >= 1 &&
              (json['leaveYearStartMonth'] as int) <= 12
          ? json['leaveYearStartMonth'] as int
          : 1,
    );
  }
}

class FlaggedCheckin {
  const FlaggedCheckin({
    required this.id,
    required this.empCode,
    required this.name,
    required this.type,
    required this.date,
    required this.serverTime,
    required this.rejectReason,
    this.nearestBranchName,
    this.distanceMeters,
    this.accuracy,
    this.isMocked,
    this.deviceId,
  });

  final String id;
  final String empCode;
  final String name;
  final String type;
  final String date;
  final String serverTime;
  final String rejectReason;
  final String? nearestBranchName;
  final double? distanceMeters;
  final double? accuracy;
  final bool? isMocked;
  final String? deviceId;

  factory FlaggedCheckin.fromJson(Map<String, dynamic> json) => FlaggedCheckin(
    id: _requiredString(json, 'id'),
    empCode: _requiredString(json, 'empCode'),
    name: _requiredString(json, 'name'),
    type: _requiredString(json, 'type'),
    date: _requiredString(json, 'date'),
    serverTime: _requiredString(json, 'serverTime'),
    rejectReason: _requiredString(json, 'rejectReason'),
    nearestBranchName: _optionalString(json, 'nearestBranchName'),
    distanceMeters: _optionalDouble(json, 'distanceMeters'),
    accuracy: _optionalDouble(json, 'accuracy'),
    isMocked: _optionalBool(json, 'isMocked'),
    deviceId: _optionalString(json, 'deviceId'),
  );
}

String _requiredString(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is String) return value;
  throw FormatException('The server returned an invalid $key value.');
}

String? _optionalString(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value == null) return null;
  if (value is String) return value;
  throw FormatException('The server returned an invalid $key value.');
}

int _requiredInt(Map<String, dynamic> json, String key) =>
    _asInt(json[key], key);

int _asInt(Object? value, String key) {
  if (value is int) return value;
  throw FormatException('The server returned an invalid $key value.');
}

int? _optionalInt(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value == null) return null;
  return _asInt(value, key);
}

double _requiredDouble(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is num && value.isFinite) return value.toDouble();
  throw FormatException('The server returned an invalid $key value.');
}

double? _optionalDouble(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value == null) return null;
  if (value is num && value.isFinite) return value.toDouble();
  throw FormatException('The server returned an invalid $key value.');
}

bool _requiredBool(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is bool) return value;
  throw FormatException('The server returned an invalid $key value.');
}

bool? _optionalBool(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value == null) return null;
  if (value is bool) return value;
  throw FormatException('The server returned an invalid $key value.');
}

List<String> _optionalStringList(Object? value) {
  if (value == null) return const [];
  if (value is! List) return const [];
  return List.unmodifiable(value.whereType<String>());
}

String? _optionalHolidayString(Object? value) {
  if (value == null) return null;
  return value is String ? value : null;
}

Map<String, dynamic> _requiredMap(Map<String, dynamic> json, String key) =>
    _asMap(json[key]);

Map<String, dynamic> _asMap(Object? value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) return value.map((key, value) => MapEntry('$key', value));
  throw const FormatException(
    'The server returned an invalid attendance response.',
  );
}
