import 'package:app/features/attendance/domain/attendance.dart';
import 'package:app/features/attendance/domain/attendance_views.dart';
import 'package:app/features/leave/domain/leave_type.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parses decimals and formats half-day values without float noise', () {
    expect(parseDecimal(0.5), 0.5);
    expect(parseDecimal(7.5), 7.5);
    expect(parseDecimal(18), 18);
    expect(parseDecimal('7.5'), 7.5);
    expect(formatDays(0.5), '0.5');
    expect(formatDays(7.5), '7.5');
    expect(formatDays(18.0), '18');
    expect(formatDays(7.499999999), '7.5');
    expect(pluralDays(1), '1 day');
    expect(pluralDays(0.5), '0.5 day');
    expect(pluralDays(2), '2 days');
  });

  test('parses employee and admin leave type shapes with missing fields', () {
    final employee = LeaveType.fromJson({
      'id': 'sick',
      'name': 'Sick Leave',
      'code': 'SL',
      'paid': true,
      'allowHalfDay': true,
      'annualQuotaDays': 8,
    });
    expect(employee.id, 'sick');
    expect(employee.status, 'active');
    expect(employee.system, isFalse);
    final admin = LeaveType.fromJson({
      'id': 'unpaid',
      'name': 'Unpaid Leave',
      'code': 'UL',
      'paid': false,
      'annualQuotaDays': null,
      'allowHalfDay': true,
      'status': 'active',
      'system': true,
      'sortOrder': 5,
      'createdAt': '2026-01-01T00:00:00.000Z',
      'updatedAt': '2026-01-02T00:00:00.000Z',
      'editedBy': 'admin-1',
    });
    expect(admin.annualQuotaDays, isNull);
    expect(admin.system, isTrue);
    expect(admin.createdAt, '2026-01-01T00:00:00.000Z');
    expect(admin.editedBy, 'admin-1');
  });

  test('parses balance decimals and null unlimited quota and remaining', () {
    final balance = LeaveBalance.fromJson({
      'year': 2026,
      'label': 'Apr 2026 - Mar 2027',
      'startDate': '2026-04-01',
      'endDate': '2027-03-31',
      'today': '2026-10-12',
      'types': [
        {
          'leaveTypeId': 'ul',
          'name': 'Unpaid Leave',
          'code': 'UL',
          'paid': false,
          'allowHalfDay': true,
          'quota': null,
          'used': 0.5,
          'pending': 1.5,
          'remaining': null,
        },
      ],
    });
    expect(balance.label, 'Apr 2026 - Mar 2027');
    expect(balance.types.single.quota, isNull);
    expect(balance.types.single.remaining, isNull);
    expect(balance.types.single.used, 0.5);
    expect(balance.types.single.pending, 1.5);
  });

  test('parses marker-only attendance and unknown calendar status safely', () {
    final raw = AttendanceDay.fromJson({
      'halfLeave': {
        'session': 'first_half',
        'paid': true,
        'leaveTypeId': 'casual',
        'leaveRequestId': 'r1',
      },
    });
    expect(raw.status, isNull);
    expect(raw.halfLeave?.session, 'first_half');

    final withStatus = AttendanceDay.fromJson({
      'status': 'P',
      'halfLeave': {
        'session': 'second_half',
        'paid': false,
        'leaveTypeId': 'ul',
        'leaveRequestId': 'r2',
      },
    });
    expect(withStatus.status, 'P');
    expect(withStatus.halfLeave?.paid, isFalse);

    final day = AttendanceCalendarDay.fromJson({
      'date': '2026-10-12',
      'weekday': 1,
      'status': 'FUTURE_STATUS',
      'derived': false,
    });
    expect(day.status, 'FUTURE_STATUS');
  });
}
