import 'package:app/features/attendance/domain/attendance_views.dart';
import 'package:app/features/attendance/domain/holiday_helpers.dart';
import 'package:app/features/branches/domain/branch.dart';
import 'package:flutter_test/flutter_test.dart';

Branch _branch(
  String id,
  String state, {
  BranchStatus status = BranchStatus.active,
}) => Branch(
  id: id,
  name: id,
  state: state,
  lat: 0,
  lng: 0,
  radiusMeters: 100,
  status: status,
  createdAt: '',
  updatedAt: '',
);

AttendanceHoliday _holiday(List<String> names) => AttendanceHoliday(
  id: 'holiday',
  date: '2026-12-23',
  name: 'Holiday',
  scope: 'branches',
  branchNames: names,
);

void main() {
  test(
    'weekday and readable date use UTC date parts at leap and year edges',
    () {
      expect(holidayWeekday('2024-02-29'), 'Thu');
      expect(readableHolidayDate('2024-02-29'), 'Thu, 29 Feb 2024');
      expect(holidayWeekday('2026-01-01'), 'Thu');
      expect(readableHolidayDate('2026-01-01'), 'Thu, 1 Jan 2026');
    },
  );

  test(
    'admin and employee scope labels cover no, one, two and many branches',
    () {
      expect(adminHolidayScopeLabel(_holiday([])), '');
      expect(adminHolidayScopeLabel(_holiday(['Chennai'])), 'Chennai');
      expect(
        adminHolidayScopeLabel(_holiday(['Chennai', 'Coimbatore'])),
        'Chennai, Coimbatore',
      );
      expect(
        adminHolidayScopeLabel(
          _holiday(['Erode', 'Chennai', 'Coimbatore', 'Madurai', 'Salem']),
        ),
        'Chennai, Coimbatore +3 more',
      );
      expect(employeeHolidayScopeLabel(_holiday([])), 'Your branch');
      expect(
        employeeHolidayScopeLabel(
          const AttendanceHoliday(id: 'x', date: '2026-01-01', name: 'x'),
        ),
        'All branches',
      );
    },
  );

  test(
    'groups active branches by normalized state and sorts state names and IDs',
    () {
      expect(
        groupBranchesByState([
          _branch('z', ' tamil nadu '),
          _branch('a', 'TAMIL NADU'),
          _branch('b', 'Kerala'),
          _branch('inactive', 'Tamil Nadu', status: BranchStatus.inactive),
        ]),
        {
          'Kerala': ['b'],
          'tamil nadu': ['a', 'z'],
        },
      );
    },
  );
}
