import assert from 'node:assert/strict';
import test from 'node:test';
import {
  classifyLeaveDates,
  classifyHalfLeaveDate,
  expandDateRange,
  monthsTouched,
  rangesOverlap,
} from './leave';

test('expands one-day, 31-day, leap-day and year-boundary ranges inclusively', () => {
  assert.deepEqual(expandDateRange('2026-02-01', '2026-02-01'), {
    ok: true,
    dates: ['2026-02-01'],
  });
  const thirtyOne = expandDateRange('2026-01-01', '2026-01-31');
  assert.equal(thirtyOne.ok, true);
  if (thirtyOne.ok) assert.equal(thirtyOne.dates.length, 31);
  assert.deepEqual(expandDateRange('2028-02-29', '2028-02-29'), {
    ok: true,
    dates: ['2028-02-29'],
  });
  assert.deepEqual(expandDateRange('2026-12-30', '2027-01-02'), {
    ok: true,
    dates: ['2026-12-30', '2026-12-31', '2027-01-01', '2027-01-02'],
  });
});

test('rejects invalid, reversed and over-31-day ranges with error values', () => {
  assert.deepEqual(expandDateRange('2026-02-30', '2026-03-01'), {
    ok: false,
    reason: 'invalid_date',
  });
  assert.deepEqual(expandDateRange('2026-03-02', '2026-03-01'), {
    ok: false,
    reason: 'from_after_to',
  });
  assert.deepEqual(expandDateRange('2026-01-01', '2026-02-01'), {
    ok: false,
    reason: 'range_too_long',
  });
});

test('returns each touched month across a year boundary once', () => {
  assert.deepEqual(monthsTouched('2026-12-30', '2027-01-02'), [
    '2026-12',
    '2027-01',
  ]);
  assert.deepEqual(monthsTouched('2028-02-28', '2028-02-29'), ['2028-02']);
});

test('treats shared endpoints as overlap but adjacent dates as separate', () => {
  assert.equal(rangesOverlap('2026-10-01', '2026-10-03', '2026-10-03', '2026-10-05'), true);
  assert.equal(rangesOverlap('2026-10-01', '2026-10-03', '2026-10-04', '2026-10-05'), false);
});

test('classifies in the required precedence and allows A, L and UL to be overwritten', () => {
  const dates = [
    '2026-10-04',
    '2026-10-05',
    '2026-10-06',
    '2026-10-07',
    '2026-10-08',
    '2026-10-09',
    '2026-10-10',
  ];
  const result = classifyLeaveDates({
    dates,
    doj: '2026-10-05',
    dol: '2026-10-10',
    holidays: new Set(['2026-10-06', '2026-10-07']),
    weeklyOffDays: [0, 1],
    days: {
      '2026-10-06': { status: 'P' },
      '2026-10-07': { status: 'H' },
      '2026-10-08': { status: 'A' },
      '2026-10-09': { status: 'L' },
      '2026-10-10': { status: 'UL' },
    },
  });
  assert.deepEqual(result, {
    toWrite: ['2026-10-08', '2026-10-09', '2026-10-10'],
    skipped: [
      { date: '2026-10-04', reason: 'outside_employment' },
      { date: '2026-10-05', reason: 'weekly_off' },
      { date: '2026-10-06', reason: 'has_punch' },
      { date: '2026-10-07', reason: 'has_punch' },
    ],
  });
});

test('classifies a holiday before a weekly off and supports custom weekdays', () => {
  assert.deepEqual(
    classifyLeaveDates({
      dates: ['2026-10-04', '2026-10-05'],
      holidays: new Set(['2026-10-04']),
      weeklyOffDays: [0, 1],
      days: {},
    }),
    {
      toWrite: [],
      skipped: [
        { date: '2026-10-04', reason: 'holiday' },
        { date: '2026-10-05', reason: 'weekly_off' },
      ],
    },
  );
});

test('full-day classification reports marker conflicts and keeps punch reasons otherwise', () => {
  const result = classifyLeaveDates({
    dates: ['2026-10-05', '2026-10-06', '2026-10-07'],
    holidays: new Set(),
    weeklyOffDays: [],
    days: {
      '2026-10-05': { status: 'A', halfLeave: { session: 'first_half' } },
      '2026-10-06': { status: 'P' },
      '2026-10-07': { status: 'P', halfLeave: { session: 'first_half' } },
    },
  });
  assert.deepEqual(result, {
    toWrite: [],
    skipped: [
      { date: '2026-10-05', reason: 'already_on_leave' },
      { date: '2026-10-06', reason: 'has_punch' },
      { date: '2026-10-07', reason: 'already_on_leave' },
    ],
  });
});

test('half-day classification reports each skip reason in precedence order', () => {
  const base = {
    weeklyOffDays: [0],
    holidayMap: new Set(['2026-10-04', '2026-10-05']),
  };
  assert.deepEqual(classifyHalfLeaveDate({
    ...base, date: '2026-10-03', doj: '2026-10-04', day: { status: 'L' },
  }), { write: false, reason: 'outside_employment' });
  assert.deepEqual(classifyHalfLeaveDate({ ...base, date: '2026-10-04' }), {
    write: false, reason: 'holiday',
  });
  assert.deepEqual(classifyHalfLeaveDate({ ...base, date: '2026-10-11' }), {
    write: false, reason: 'weekly_off',
  });
  assert.deepEqual(classifyHalfLeaveDate({ ...base, date: '2026-10-05', day: { status: 'L' } }), {
    write: false, reason: 'holiday',
  });
  assert.deepEqual(classifyHalfLeaveDate({
    ...base, date: '2026-10-06', day: { status: 'UL' },
  }), { write: false, reason: 'already_on_leave' });
  assert.deepEqual(classifyHalfLeaveDate({
    ...base, date: '2026-10-06', day: { halfLeave: { paid: true } },
  }), { write: false, reason: 'already_on_leave' });
  assert.deepEqual(classifyHalfLeaveDate({
    ...base, date: '2026-10-06', day: { status: 'H' },
  }), { write: false, reason: 'half_day_marked' });
  assert.deepEqual(classifyHalfLeaveDate({
    ...base, date: '2026-10-06', day: { status: 'P' },
  }), { write: true });
  assert.deepEqual(classifyHalfLeaveDate({
    ...base, date: '2026-10-06', day: { status: 'A' },
  }), { write: true });
  assert.deepEqual(classifyHalfLeaveDate({ ...base, date: '2026-10-06' }), { write: true });
});
