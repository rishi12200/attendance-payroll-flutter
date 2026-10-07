import assert from 'node:assert/strict';
import test from 'node:test';
import {
  compareDateStrings,
  istDateOf,
  isDateBefore,
  isDateOnOrBefore,
  isValidDateString,
  monthOf,
  todayIST,
} from './dates';

test('todayIST applies a fixed +05:30 offset across UTC day boundaries', () => {
  assert.equal(todayIST(new Date('2026-10-06T18:29:59.000Z')), '2026-10-06');
  assert.equal(todayIST(new Date('2026-10-06T18:30:00.000Z')), '2026-10-07');
});

test('istDateOf changes dates at the fixed IST midnight boundary', () => {
  assert.equal(istDateOf(new Date('2026-10-06T18:29:59.000Z')), '2026-10-06');
  assert.equal(istDateOf(new Date('2026-10-06T18:30:00.000Z')), '2026-10-07');
});

test('monthOf returns the month from a valid date string', () => {
  assert.equal(monthOf('2026-10-07'), '2026-10');
  assert.throws(() => monthOf('2026-13-07'), RangeError);
});

test('validates exact calendar date strings', () => {
  assert.equal(isValidDateString('2024-02-29'), true);
  assert.equal(isValidDateString('2025-02-29'), false);
  assert.equal(isValidDateString('2026-13-01'), false);
  assert.equal(isValidDateString('2026-1-01'), false);
  assert.equal(isValidDateString(20261007), false);
});

test('compares valid date strings chronologically', () => {
  assert.equal(compareDateStrings('2026-10-06', '2026-10-07'), -1);
  assert.equal(compareDateStrings('2026-10-07', '2026-10-07'), 0);
  assert.equal(compareDateStrings('2026-10-08', '2026-10-07'), 1);
  assert.equal(isDateBefore('2026-10-06', '2026-10-07'), true);
  assert.equal(isDateOnOrBefore('2026-10-07', '2026-10-07'), true);
  assert.throws(() => compareDateStrings('not-a-date', '2026-10-07'), RangeError);
});
