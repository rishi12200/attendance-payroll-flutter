import 'package:app/features/attendance/domain/attendance_views.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, Object?> summaryJson() => {
  'daysInMonth': 31,
  'weeklyOffs': 4,
  'holidays': 1,
  'present': 18,
  'halfDays': 1,
  'absent': 2,
  'paidLeave': 1,
  'unpaidLeave': 1,
  'notJoinedOrLeftDays': 0,
  'pending': 3,
  'lop': 3.5,
  'payableDays': 27.5,
};

void main() {
  test(
    'parses attendance calendar day with missing or null optional fields',
    () {
      final missing = AttendanceCalendarDay.fromJson({
        'date': '2026-10-08',
        'weekday': 4,
        'status': 'PENDING',
        'derived': false,
      });
      expect(missing.holidayName, isNull);
      expect(missing.inTime, isNull);
      expect(missing.editedAt, isNull);

      final nullable = AttendanceCalendarDay.fromJson({
        'date': '2026-10-08',
        'weekday': 4,
        'status': 'P',
        'derived': false,
        'inTime': null,
        'holidayName': null,
        'workedMinutes': null,
      });
      expect(nullable.inTime, isNull);
      expect(nullable.holidayName, isNull);
      expect(nullable.workedMinutes, isNull);
    },
  );

  test('parses calendar and summary values defensively', () {
    final calendar = AttendanceCalendar.fromJson({
      'month': '2026-10',
      'today': '2026-10-08',
      'serverTime': '2026-10-08T07:19:12.000Z',
      'summary': summaryJson(),
      'days': [
        {
          'date': '2026-10-08',
          'weekday': 4,
          'status': 'PENDING',
          'derived': false,
        },
      ],
    });
    expect(calendar.days, hasLength(1));
    expect(calendar.summary.lop, 3.5);
    expect(calendar.summary.payableDays, 27.5);
  });

  test('parses optional fields from admin attendance rows', () {
    final row = AttendanceDateRow.fromJson({
      'empId': 'employee-1',
      'empCode': 'EMP001',
      'name': 'Asha',
      'status': 'A',
      'derived': true,
      'noCheckout': false,
      'checkedInNow': false,
      'designation': null,
      'inTime': null,
    });
    expect(row.designation, isNull);
    expect(row.inTime, isNull);
    expect(row.noCheckout, isFalse);
  });

  test('parses date totals and month summary rows', () {
    final date = AttendanceByDate.fromJson({
      'date': '2026-10-08',
      'today': '2026-10-08',
      'totals': {'P': 1, 'A': 0},
      'rows': [],
    });
    expect(date.totals, {'P': 1, 'A': 0});

    final row = AttendanceMonthSummaryRow.fromJson({
      'empId': 'employee-1',
      'empCode': 'EMP001',
      'name': 'Asha',
      'summary': summaryJson(),
    });
    expect(row.summary.present, 18);
    expect(row.empCode, 'EMP001');
  });

  test('parses holidays, settings and flagged check-ins', () {
    final holiday = AttendanceHoliday.fromJson({
      'date': '2026-10-08',
      'name': 'Founders day',
    });
    expect(holiday.name, 'Founders day');

    final settings = AttendanceSettings.fromJson({
      'companyName': '',
      'weeklyOffDays': [0, 6],
      'perDayBasis': 'calendar',
      'maxAccuracyMeters': 100,
      'rejectMockLocation': true,
      'enforceCheckoutLocation': false,
    });
    expect(settings.weeklyOffDays, [0, 6]);

    final flagged = FlaggedCheckin.fromJson({
      'id': 'attempt-1',
      'empCode': 'EMP001',
      'name': 'Asha',
      'type': 'in',
      'date': '2026-10-08',
      'serverTime': '2026-10-08T07:19:12.000Z',
      'rejectReason': 'OUTSIDE_GEOFENCE',
      'nearestBranchName': null,
      'distanceMeters': null,
      'accuracy': null,
      'isMocked': null,
      'deviceId': null,
    });
    expect(flagged.nearestBranchName, isNull);
    expect(flagged.isMocked, isNull);
  });

  test('rejects malformed required values', () {
    expect(
      () => AttendanceHoliday.fromJson({'date': '2026-10-08'}),
      throwsFormatException,
    );
    expect(
      () => AttendanceSummary.fromJson({'daysInMonth': null}),
      throwsFormatException,
    );
  });
}
