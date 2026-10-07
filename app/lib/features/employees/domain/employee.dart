enum EmployeeStatus { active, inactive }

class Employee {
  const Employee({
    required this.uid,
    required this.empCode,
    required this.name,
    required this.email,
    required this.role,
    required this.status,
    required this.doj,
    required this.createdAt,
    required this.updatedAt,
    this.phone,
    this.designation,
    this.dol,
    this.editedBy,
    this.editedAt,
    this.currentMonthlyCtcPaise,
  });

  final String uid;
  final String empCode;
  final String name;
  final String email;
  final String role;
  final EmployeeStatus status;
  final String doj;
  final String createdAt;
  final String updatedAt;
  final String? phone;
  final String? designation;
  final String? dol;
  final String? editedBy;
  final String? editedAt;
  final int? currentMonthlyCtcPaise;

  factory Employee.fromJson(Map<String, dynamic> json) {
    final uid = json['uid'];
    final empCode = json['empCode'];
    final name = json['name'];
    final email = json['email'];
    final role = json['role'];
    final status = switch (json['status']) {
      'active' => EmployeeStatus.active,
      'inactive' => EmployeeStatus.inactive,
      _ => null,
    };
    final doj = json['doj'];
    final createdAt = json['createdAt'];
    final updatedAt = json['updatedAt'];
    final salary = json['currentMonthlyCtcPaise'];

    if (uid is! String ||
        empCode is! String ||
        name is! String ||
        email is! String ||
        role is! String ||
        status == null ||
        doj is! String ||
        createdAt is! String ||
        updatedAt is! String ||
        (salary != null && salary is! int)) {
      throw const FormatException('The server returned an invalid employee.');
    }

    return Employee(
      uid: uid,
      empCode: empCode,
      name: name,
      email: email,
      role: role,
      status: status,
      doj: doj,
      createdAt: createdAt,
      updatedAt: updatedAt,
      phone: _optionalString(json['phone']),
      designation: _optionalString(json['designation']),
      dol: _optionalString(json['dol']),
      editedBy: _optionalString(json['editedBy']),
      editedAt: _optionalString(json['editedAt']),
      currentMonthlyCtcPaise: salary as int?,
    );
  }
}

String? _optionalString(Object? value) {
  if (value == null) return null;
  if (value is String) return value;
  throw const FormatException('The server returned an invalid employee.');
}
