import assert from 'node:assert/strict';
import test from 'node:test';
import {
  attendanceSettingsFromDocument,
  DEFAULT_ATTENDANCE_SETTINGS,
  workedMinutes,
} from './attendance';

test('workedMinutes floors partial minutes and never returns a negative value', () => {
  const start = new Date('2026-10-07T10:00:00.000Z');
  assert.equal(
    workedMinutes(start, new Date('2026-10-07T11:12:59.999Z')),
    72,
  );
  assert.equal(workedMinutes(start, new Date('2026-10-07T09:00:00.000Z')), 0);
});

test('attendance settings use defaults for a missing document or fields', () => {
  assert.deepEqual(attendanceSettingsFromDocument(undefined), {
    maxAccuracyMeters: 100,
    rejectMockLocation: true,
    enforceCheckoutLocation: false,
  });
  assert.deepEqual(attendanceSettingsFromDocument({}), {
    ...DEFAULT_ATTENDANCE_SETTINGS,
  });
  assert.deepEqual(
    attendanceSettingsFromDocument({
      maxAccuracyMeters: 75,
      enforceCheckoutLocation: true,
    }),
    {
      maxAccuracyMeters: 75,
      rejectMockLocation: true,
      enforceCheckoutLocation: true,
    },
  );
});

test('attendance settings reject invalid stored values', () => {
  assert.throws(() => attendanceSettingsFromDocument({ maxAccuracyMeters: -1 }));
  assert.throws(() => attendanceSettingsFromDocument({ rejectMockLocation: 1 }));
});
