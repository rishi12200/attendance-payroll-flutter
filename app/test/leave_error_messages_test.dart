import 'package:app/core/api/app_exception.dart';
import 'package:app/features/leave/presentation/apply_leave_screen.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('maps leave application errors to friendly messages', () {
    const expected = {
      'NO_WORKING_DAYS': 'This range has no working days (weekly offs and holidays are not counted).',
      'NOT_A_WORKING_DAY': 'Half-day leave must be requested on a working day.',
      'HALF_DAY_SINGLE_DATE': 'A half-day request must cover exactly one date.',
      'HALF_DAY_NOT_ALLOWED': "This leave type doesn't allow half days.",
      'LEAVE_TYPE_INACTIVE':
          'This leave type is no longer available. Choose another type.',
      'LEAVE_TYPE_MISSING':
          'This older request has no leave type and cannot be approved.',
      'LEAVE_OVERLAP':
          'You already have a leave request covering some of these dates.',
      'MONTH_LOCKED':
          'This month is locked, so leave cannot be requested for these dates.',
      'OUTSIDE_EMPLOYMENT_WINDOW':
          'Leave dates must fall within your employment dates.',
      'LEAVE_RANGE_TOO_LONG': 'A leave request cannot exceed 31 days.',
      'INVALID_DATE_RANGE': 'Choose a valid date range.',
      'LEAVE_TYPE_NOT_FOUND':
          'This leave type is no longer available. Choose another type.',
    };
    for (final entry in expected.entries) {
      expect(
        leaveErrorMessage(
          AppException(code: entry.key, message: 'server', details: {}),
        ),
        entry.value,
      );
    }
  });

  test('formats quota details defensively and falls back without them', () {
    expect(
      leaveErrorMessage(
        const AppException(
          code: 'QUOTA_EXCEEDED',
          message: 'Quota exceeded',
          details: {
            'leaveTypeName': 'Sick Leave',
            'yearLabel': '2026',
            'remaining': 1.5,
            'requested': 2,
          },
        ),
      ),
      'Not enough Sick Leave left for 2026: 1.5 days left, you asked for 2.',
    );
    expect(
      leaveErrorMessage(
        const AppException(
          code: 'QUOTA_EXCEEDED',
          message: 'Server quota message',
          details: {},
        ),
      ),
      'Server quota message',
    );
  });
}
