enum LeaveStatus { pending, approved, rejected, cancelled }

enum LeaveType { paid, unpaid }

class SkippedDate {
  const SkippedDate({required this.date, required this.reason});

  final String date;
  final String reason;

  factory SkippedDate.fromJson(Map<String, dynamic> json) => SkippedDate(
    date: _string(json['date']) ?? '',
    reason: _string(json['reason']) ?? '',
  );
}

class LeaveRequest {
  const LeaveRequest({
    required this.id,
    required this.empId,
    required this.fromDate,
    required this.toDate,
    required this.reason,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    this.leaveType,
    this.decidedBy,
    this.decidedAt,
    this.decisionNote,
    this.writtenDates = const [],
    this.skippedDates = const [],
    this.noDaysWritten = false,
    this.empCode,
    this.name,
    this.designation,
  });

  final String id;
  final String empId;
  final String fromDate;
  final String toDate;
  final String reason;
  final LeaveStatus status;
  final String createdAt;
  final String updatedAt;
  final LeaveType? leaveType;
  final String? decidedBy;
  final String? decidedAt;
  final String? decisionNote;
  final List<String> writtenDates;
  final List<SkippedDate> skippedDates;
  final bool noDaysWritten;
  final String? empCode;
  final String? name;
  final String? designation;

  factory LeaveRequest.fromJson(Map<String, dynamic> json) {
    final statusValue = _string(json['status']);
    final status = LeaveStatus.values
        .where((value) => value.name == statusValue)
        .firstOrNull;
    final leaveTypeValue = _string(json['leaveType']);
    final leaveType = LeaveType.values
        .where((value) => value.name == leaveTypeValue)
        .firstOrNull;
    return LeaveRequest(
      id: _string(json['id']) ?? '',
      empId: _string(json['empId']) ?? '',
      fromDate: _string(json['fromDate']) ?? '',
      toDate: _string(json['toDate']) ?? '',
      reason: _string(json['reason']) ?? '',
      status: status ?? LeaveStatus.pending,
      createdAt: _string(json['createdAt']) ?? '',
      updatedAt: _string(json['updatedAt']) ?? '',
      leaveType: leaveType,
      decidedBy: _string(json['decidedBy']),
      decidedAt: _string(json['decidedAt']),
      decisionNote: _string(json['decisionNote']),
      writtenDates: _stringList(json['writtenDates']),
      skippedDates: _skippedList(json['skippedDates']),
      noDaysWritten: json['noDaysWritten'] == true,
      empCode: _string(json['empCode']),
      name: _string(json['name']),
      designation: _string(json['designation']),
    );
  }
}

String? _string(Object? value) => value is String ? value : null;

List<String> _stringList(Object? value) => value is List
    ? value.whereType<String>().toList(growable: false)
    : const [];

List<SkippedDate> _skippedList(Object? value) => value is List
    ? value
          .whereType<Map>()
          .map(
            (item) => SkippedDate.fromJson(
              item.map((key, value) => MapEntry('$key', value)),
            ),
          )
          .toList(growable: false)
    : const [];
