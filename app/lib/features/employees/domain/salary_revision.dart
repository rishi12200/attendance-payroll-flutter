class SalaryRevision {
  const SalaryRevision({
    required this.empId,
    required this.effectiveFrom,
    required this.monthlyCtcPaise,
  });

  final String empId;
  final String effectiveFrom;
  final int monthlyCtcPaise;

  factory SalaryRevision.fromJson(Map<String, dynamic> json) {
    final empId = json['empId'];
    final effectiveFrom = json['effectiveFrom'];
    final monthlyCtcPaise = json['monthlyCtcPaise'];
    if (empId is! String ||
        effectiveFrom is! String ||
        monthlyCtcPaise is! int) {
      throw const FormatException('The server returned an invalid salary revision.');
    }
    return SalaryRevision(
      empId: empId,
      effectiveFrom: effectiveFrom,
      monthlyCtcPaise: monthlyCtcPaise,
    );
  }
}
