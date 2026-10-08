import 'package:app/features/leave/domain/leave_helpers.dart';
import 'package:app/features/leave/domain/leave_request.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parses required leave fields and tolerates missing optional fields', () {
    final request = LeaveRequest.fromJson({
      'id': 'leave-1',
      'empId': 'emp-1',
      'fromDate': '2026-10-12',
      'toDate': '2026-10-14',
      'reason': 'Family event',
      'status': 'pending',
      'createdAt': '2026-10-08T10:00:00.000Z',
      'updatedAt': '2026-10-08T10:00:00.000Z',
    });
    expect(request.status, LeaveStatus.pending);
    expect(request.leaveType, isNull);
    expect(request.decidedBy, isNull);
    expect(request.writtenDates, isEmpty);
    expect(request.skippedDates, isEmpty);
    expect(request.empCode, isNull);
  });

  test('parses approval fields and ignores malformed optional values', () {
    final request = LeaveRequest.fromJson({
      'id': 'leave-2', 'empId': 'emp-1', 'fromDate': '2026-10-12',
      'toDate': '2026-10-14', 'reason': 'Family event', 'status': 'approved',
      'createdAt': 'created', 'updatedAt': 'updated', 'leaveType': 'paid',
      'decidedBy': 5, 'decidedAt': 'decided', 'decisionNote': null,
      'writtenDates': ['2026-10-12', 7],
      'skippedDates': [{'date': '2026-10-13', 'reason': 'holiday'}, null],
      'noDaysWritten': true, 'name': 'Asha', 'empCode': 'EMP001',
      'designation': 'Associate',
    });
    expect(request.leaveType, LeaveType.paid);
    expect(request.decidedBy, isNull);
    expect(request.writtenDates, ['2026-10-12']);
    expect(request.skippedDates.single.reason, 'holiday');
    expect(request.noDaysWritten, isTrue);
    expect(request.name, 'Asha');
    expect(request.empCode, 'EMP001');
    expect(request.designation, 'Associate');
  });

  test('counts inclusive leave days across month and year boundaries', () {
    expect(leaveDayCount('2026-10-30', '2026-11-02'), 4);
    expect(leaveDayCount('2026-12-31', '2027-01-02'), 3);
    expect(leaveDayCount('2026-10-12', '2026-10-12'), 1);
  });

  test('formats date ranges across same month, month and year boundaries', () {
    expect(readableLeaveRange('2026-10-12', '2026-10-14'), '12 - 14 Oct 2026');
    expect(readableLeaveRange('2026-10-30', '2026-11-02'), '30 Oct - 2 Nov 2026');
    expect(readableLeaveRange('2026-12-31', '2027-01-02'), '31 Dec 2026 - 2 Jan 2027');
    expect(readableLeaveRange('2026-10-12', '2026-10-12'), '12 Oct 2026');
  });

  test('labels each supported skip reason', () {
    expect(skippedReasonLabel('weekly_off'), 'Sunday / weekly off');
    expect(skippedReasonLabel('holiday'), 'Holiday');
    expect(skippedReasonLabel('has_punch'), 'Already has attendance');
    expect(skippedReasonLabel('outside_employment'), 'Outside employment dates');
  });
}
