class AttendanceDay {
  const AttendanceDay({
    required this.status,
    this.inTime,
    this.outTime,
    this.inBranchId,
    this.outBranchId,
    this.inDistance,
    this.outDistance,
    this.workedMinutes,
    this.source,
  });

  final String status;
  final String? inTime;
  final String? outTime;
  final String? inBranchId;
  final String? outBranchId;
  final double? inDistance;
  final double? outDistance;
  final int? workedMinutes;
  final String? source;

  factory AttendanceDay.fromJson(Map<String, dynamic> json) {
    final status = json['status'];
    if (status is! String) {
      throw const FormatException('The server returned an invalid attendance day.');
    }
    return AttendanceDay(
      status: status,
      inTime: _optionalString(json['inTime']),
      outTime: _optionalString(json['outTime']),
      inBranchId: _optionalString(json['inBranchId']),
      outBranchId: _optionalString(json['outBranchId']),
      inDistance: _optionalDouble(json['inDistance']),
      outDistance: _optionalDouble(json['outDistance']),
      workedMinutes: _optionalInt(json['workedMinutes']),
      source: _optionalString(json['source']),
    );
  }
}

class MonthAttendance {
  const MonthAttendance({
    required this.month,
    required this.today,
    required this.serverTime,
    required this.days,
  });

  final String month;
  final String today;
  final String serverTime;
  final Map<String, AttendanceDay> days;

  factory MonthAttendance.fromJson(Map<String, dynamic> json) {
    final month = json['month'];
    final today = json['today'];
    final serverTime = json['serverTime'];
    final rawDays = json['days'];
    if (month is! String ||
        today is! String ||
        serverTime is! String ||
        rawDays is! Map) {
      throw const FormatException('The server returned invalid monthly attendance.');
    }
    final days = <String, AttendanceDay>{};
    for (final entry in rawDays.entries) {
      if (entry.key is! String || entry.value is! Map) {
        throw const FormatException('The server returned an invalid attendance day.');
      }
      days[entry.key as String] = AttendanceDay.fromJson(
        _asJsonMap(entry.value),
      );
    }
    return MonthAttendance(
      month: month,
      today: today,
      serverTime: serverTime,
      days: Map.unmodifiable(days),
    );
  }
}

class CheckInResult {
  const CheckInResult({
    required this.date,
    required this.status,
    required this.inTime,
    required this.branchId,
    required this.distanceMeters,
    this.branchName,
  });

  final String date;
  final String status;
  final String inTime;
  final String branchId;
  final String? branchName;
  final double distanceMeters;

  factory CheckInResult.fromJson(Map<String, dynamic> json) {
    final date = json['date'];
    final status = json['status'];
    final inTime = json['inTime'];
    final branchId = json['branchId'];
    final distance = json['distanceMeters'];
    if (date is! String ||
        status is! String ||
        inTime is! String ||
        branchId is! String ||
        distance is! num) {
      throw const FormatException('The server returned an invalid check-in response.');
    }
    return CheckInResult(
      date: date,
      status: status,
      inTime: inTime,
      branchId: branchId,
      branchName: _optionalString(json['branchName']),
      distanceMeters: distance.toDouble(),
    );
  }
}

class CheckOutResult {
  const CheckOutResult({
    required this.date,
    required this.inTime,
    required this.outTime,
    required this.workedMinutes,
    required this.branchId,
    required this.distanceMeters,
    this.branchName,
  });

  final String date;
  final String inTime;
  final String outTime;
  final int workedMinutes;
  final String? branchId;
  final String? branchName;
  final double? distanceMeters;

  factory CheckOutResult.fromJson(Map<String, dynamic> json) {
    final date = json['date'];
    final inTime = json['inTime'];
    final outTime = json['outTime'];
    final workedMinutes = json['workedMinutes'];
    if (date is! String ||
        inTime is! String ||
        outTime is! String ||
        workedMinutes is! int) {
      throw const FormatException('The server returned an invalid check-out response.');
    }
    return CheckOutResult(
      date: date,
      inTime: inTime,
      outTime: outTime,
      workedMinutes: workedMinutes,
      branchId: _optionalString(json['branchId']),
      branchName: _optionalString(json['branchName']),
      distanceMeters: _optionalDouble(json['distanceMeters']),
    );
  }
}

String? _optionalString(Object? value) {
  if (value == null) return null;
  if (value is String) return value;
  throw const FormatException('The server returned an invalid attendance value.');
}

double? _optionalDouble(Object? value) {
  if (value == null) return null;
  if (value is num && value.isFinite) return value.toDouble();
  throw const FormatException('The server returned an invalid attendance value.');
}

int? _optionalInt(Object? value) {
  if (value == null) return null;
  if (value is int) return value;
  throw const FormatException('The server returned an invalid attendance value.');
}

Map<String, dynamic> _asJsonMap(Object? value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) return value.map((key, item) => MapEntry('$key', item));
  throw const FormatException('The server returned an invalid attendance day.');
}
