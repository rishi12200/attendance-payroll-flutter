import assert from 'node:assert/strict';
import test from 'node:test';
import {
  attendanceMonthQuerySchema,
  punchBodySchema,
} from './attendance-schemas';

const validPunch = {
  lat: 13.08,
  lng: 80.27,
  accuracy: 12,
  deviceId: 'android-emulator',
  isMocked: false,
};

test('validates bounded punch coordinates, accuracy and device metadata', () => {
  assert.equal(punchBodySchema.safeParse(validPunch).success, true);
  assert.equal(punchBodySchema.safeParse({ ...validPunch, lat: 90.01 }).success, false);
  assert.equal(punchBodySchema.safeParse({ ...validPunch, lng: -180.01 }).success, false);
  assert.equal(punchBodySchema.safeParse({ ...validPunch, accuracy: -1 }).success, false);
  assert.equal(punchBodySchema.safeParse({ ...validPunch, deviceId: ' ' }).success, false);
  assert.equal(punchBodySchema.safeParse({ ...validPunch, deviceId: 'd'.repeat(101) }).success, false);
});

test('rejects client-supplied server timestamps and unknown punch fields', () => {
  assert.equal(
    punchBodySchema.safeParse({
      ...validPunch,
      time: '2026-10-07T00:00:00Z',
    }).success,
    false,
  );
});

test('validates YYYY-MM attendance queries', () => {
  assert.equal(attendanceMonthQuerySchema.safeParse({ month: '2026-10' }).success, true);
  assert.equal(attendanceMonthQuerySchema.safeParse({ month: '2026-13' }).success, false);
  assert.equal(attendanceMonthQuerySchema.safeParse({ month: '2026-1' }).success, false);
});
