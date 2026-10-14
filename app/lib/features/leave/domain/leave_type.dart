class LeaveType {
  const LeaveType({
    required this.id,
    required this.name,
    required this.code,
    required this.paid,
    required this.annualQuotaDays,
    required this.allowHalfDay,
    this.status = 'active',
    this.system = false,
    this.sortOrder = 0,
    this.createdAt,
    this.updatedAt,
    this.editedBy,
  });

  final String id;
  final String name;
  final String code;
  final bool paid;
  final double? annualQuotaDays;
  final bool allowHalfDay;
  final String status;
  final bool system;
  final int sortOrder;
  final String? createdAt;
  final String? updatedAt;
  final String? editedBy;

  factory LeaveType.fromJson(Map<String, dynamic> json) => LeaveType(
    id: _string(json['id']) ?? '',
    name: _string(json['name']) ?? 'Leave type',
    code: _string(json['code']) ?? '',
    paid: json['paid'] is bool ? json['paid'] as bool : true,
    annualQuotaDays: parseNullableDecimal(json['annualQuotaDays']),
    allowHalfDay: json['allowHalfDay'] is bool
        ? json['allowHalfDay'] as bool
        : false,
    status: _string(json['status']) ?? 'active',
    system: json['system'] is bool ? json['system'] as bool : false,
    sortOrder: json['sortOrder'] is num
        ? (json['sortOrder'] as num).toInt()
        : 0,
    createdAt: _string(json['createdAt']),
    updatedAt: _string(json['updatedAt']),
    editedBy: _string(json['editedBy']),
  );

  static String? _string(Object? value) => value is String ? value : null;
}

class BalanceType {
  const BalanceType({
    required this.leaveTypeId,
    required this.name,
    required this.code,
    required this.paid,
    required this.allowHalfDay,
    required this.quota,
    required this.used,
    required this.pending,
    required this.remaining,
  });

  final String leaveTypeId;
  final String name;
  final String code;
  final bool paid;
  final bool allowHalfDay;
  final double? quota;
  final double used;
  final double pending;
  final double? remaining;

  factory BalanceType.fromJson(Map<String, dynamic> json) => BalanceType(
    leaveTypeId: json['leaveTypeId'] is String
        ? json['leaveTypeId'] as String
        : '',
    name: json['name'] is String ? json['name'] as String : 'Leave type',
    code: json['code'] is String ? json['code'] as String : '',
    paid: json['paid'] is bool ? json['paid'] as bool : true,
    allowHalfDay: json['allowHalfDay'] is bool
        ? json['allowHalfDay'] as bool
        : false,
    quota: parseNullableDecimal(json['quota']),
    used: parseDecimal(json['used']),
    pending: parseDecimal(json['pending']),
    remaining: parseNullableDecimal(json['remaining']),
  );
}

class LeaveBalance {
  const LeaveBalance({
    required this.year,
    required this.label,
    required this.startDate,
    required this.endDate,
    required this.today,
    required this.types,
  });

  final int year;
  final String label;
  final String startDate;
  final String endDate;
  final String today;
  final List<BalanceType> types;

  factory LeaveBalance.fromJson(Map<String, dynamic> json) => LeaveBalance(
    year: json['year'] is num ? (json['year'] as num).toInt() : 2000,
    label: json['label'] is String ? json['label'] as String : '',
    startDate: json['startDate'] is String ? json['startDate'] as String : '',
    endDate: json['endDate'] is String ? json['endDate'] as String : '',
    today: json['today'] is String ? json['today'] as String : '',
    types: json['types'] is List
        ? List.unmodifiable(
            (json['types'] as List).whereType<Map>().map(
              (item) =>
                  BalanceType.fromJson(item.map((k, v) => MapEntry('$k', v))),
            ),
          )
        : const [],
  );
}

double parseDecimal(Object? value) {
  if (value is num && value.isFinite) return value.toDouble();
  if (value is String) return double.tryParse(value.trim()) ?? 0;
  return 0;
}

double? parseNullableDecimal(Object? value) => value == null
    ? null
    : (value is String && value.trim().isEmpty ? null : parseDecimal(value));

String formatDays(double value) {
  final rounded = (value * 2).round() / 2;
  if ((value - rounded).abs() < 0.000001) value = rounded;
  if (value == value.roundToDouble()) return value.toInt().toString();
  return value.toString();
}

String pluralDays(double value) =>
    '${formatDays(value)} ${value == 1 || value == 0.5 ? 'day' : 'days'}';

String paidLabel(bool paid) => paid ? 'Paid' : 'Unpaid';

String sessionLabel(String? session) => switch (session) {
  'first_half' => 'First half',
  'second_half' => 'Second half',
  _ => 'Full day',
};
