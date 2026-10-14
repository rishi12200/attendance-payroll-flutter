import assert from 'node:assert/strict';
import test from 'node:test';
import { leaveYearByYear, leaveYearOf } from './leave-year';

test('January leave year follows the calendar year', () => {
  assert.deepEqual(leaveYearOf('2026-01-01', 1), {
    year: 2026,
    startDate: '2026-01-01',
    endDate: '2026-12-31',
    label: '2026',
  });
  assert.deepEqual(leaveYearOf('2026-12-31', 1), leaveYearByYear(2026, 1));
});

test('April leave year spans April through March and crosses its boundary', () => {
  assert.deepEqual(leaveYearOf('2026-04-01', 4), {
    year: 2026,
    startDate: '2026-04-01',
    endDate: '2027-03-31',
    label: 'Apr 2026 - Mar 2027',
  });
  assert.equal(leaveYearOf('2027-03-31', 4).year, 2026);
  assert.equal(leaveYearOf('2027-04-01', 4).year, 2027);
});

test('December leave year handles the first and last days', () => {
  assert.deepEqual(leaveYearOf('2026-11-30', 12), {
    year: 2025,
    startDate: '2025-12-01',
    endDate: '2026-11-30',
    label: 'Dec 2025 - Nov 2026',
  });
  assert.equal(leaveYearOf('2026-12-01', 12).year, 2026);
  assert.equal(leaveYearByYear(2026, 12).endDate, '2027-11-30');
});

test('leave year end dates use leap-day rules', () => {
  assert.equal(leaveYearByYear(2024, 3).endDate, '2025-02-28');
  assert.equal(leaveYearByYear(2023, 3).endDate, '2024-02-29');
  assert.equal(leaveYearOf('2024-02-29', 4).year, 2023);
});

test('rejects invalid dates, years and start months', () => {
  assert.throws(() => leaveYearOf('2026-02-30', 1), RangeError);
  assert.throws(() => leaveYearOf('2026-01-01', 13), RangeError);
  assert.throws(() => leaveYearByYear(2026.5, 1), RangeError);
});
