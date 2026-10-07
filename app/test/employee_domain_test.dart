import 'package:app/features/employees/domain/employee.dart';
import 'package:app/features/employees/domain/employee_dates.dart';
import 'package:app/features/employees/domain/money.dart';
import 'package:app/features/employees/domain/salary_revision.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('money helpers', () {
    test('parses paise using integer arithmetic', () {
      expect(rupeesStringToPaise('25,000.50'), 2500050);
      expect(rupeesStringToPaise('25000'), 2500000);
      expect(rupeesStringToPaise('1.2'), 120);
    });

    test('formats paise using Indian digit grouping', () {
      expect(paiseToDisplay(2500050), '₹25,000.50');
      expect(paiseToDisplay(123456789), '₹12,34,567.89');
      expect(paiseToDisplay(9), '₹0.09');
    });

    test('rejects invalid rupee inputs', () {
      for (final value in [
        '',
        '0',
        '0.00',
        '-1',
        '+1',
        '1.234',
        '1.',
        '.50',
        '1,0000',
        '1,00,00',
      ]) {
        expect(rupeesStringToPaise(value), isNull, reason: value);
      }
    });
  });

  group('date helpers', () {
    test('parses and formats YYYY-MM-DD dates', () {
      expect(formatDate(parseDate('2026-10-07')), '2026-10-07');
      expect(() => parseDate('2026-02-30'), throwsFormatException);
      expect(() => parseDate('07-10-2026'), throwsFormatException);
    });

    test('calculates today using a fixed IST offset', () {
      expect(todayIST(DateTime.utc(2026, 10, 7, 18, 30)), '2026-10-08');
    });
  });

  group('employee parsing', () {
    final requiredFields = {
      'uid': 'employee-1',
      'empCode': 'EMP001',
      'name': 'Test Employee',
      'email': 'test@example.com',
      'role': 'employee',
      'status': 'active',
      'doj': '2026-10-01',
      'createdAt': '2026-10-07T10:00:00.000Z',
      'updatedAt': '2026-10-07T10:00:00.000Z',
    };

    test('accepts missing or null optional fields', () {
      final missing = Employee.fromJson(requiredFields);
      final nullable = Employee.fromJson({
        ...requiredFields,
        'phone': null,
        'designation': null,
        'dol': null,
        'editedBy': null,
        'editedAt': null,
        'currentMonthlyCtcPaise': null,
      });

      expect(missing.phone, isNull);
      expect(missing.dol, isNull);
      expect(nullable.currentMonthlyCtcPaise, isNull);
      expect(nullable.editedAt, isNull);
    });

    test('rejects malformed required fields and non-integer salary', () {
      expect(
        () => Employee.fromJson({
          ...requiredFields,
          'currentMonthlyCtcPaise': 1.2,
        }),
        throwsFormatException,
      );
      expect(
        () => Employee.fromJson({...requiredFields, 'status': 'deleted'}),
        throwsFormatException,
      );
    });
  });

  test('parses salary revisions with integer paise', () {
    final revision = SalaryRevision.fromJson({
      'empId': 'employee-1',
      'effectiveFrom': '2026-10-01',
      'monthlyCtcPaise': 2500050,
    });
    expect(revision.monthlyCtcPaise, 2500050);
    expect(
      () => SalaryRevision.fromJson({
        'empId': 'employee-1',
        'effectiveFrom': '2026-10-01',
        'monthlyCtcPaise': 1.2,
      }),
      throwsFormatException,
    );
  });
}
