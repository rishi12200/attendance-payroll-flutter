import assert from 'node:assert/strict';
import test from 'node:test';
import { buildMonthCalendar } from './attendance-calendar';

function calendar(
  options: Partial<Parameters<typeof buildMonthCalendar>[0]> = {},
) {
  return buildMonthCalendar({
    month: '2028-02',
    today: '2028-02-15',
    days: {},
    holidays: {},
    weeklyOffDays: [0],
    ...options,
  });
}

test('builds 28, 29, 30 and 31 day months', () => {
  assert.equal(calendar({ month: '2027-02' }).days.length, 28);
  assert.equal(calendar({ month: '2028-02' }).days.length, 29);
  assert.equal(calendar({ month: '2028-04' }).days.length, 30);
  assert.equal(calendar({ month: '2028-01' }).days.length, 31);
});

test('applies joiner and leaver boundaries inclusively', () => {
  const result = calendar({
    month: '2028-02',
    today: '2028-02-29',
    doj: '2028-02-10',
    dol: '2028-02-20',
    weeklyOffDays: [],
  });
  assert.equal(result.days[0]?.status, 'NOT_JOINED');
  assert.equal(result.days[9]?.status, 'A');
  assert.equal(result.days[19]?.status, 'A');
  assert.equal(result.days[20]?.status, 'LEFT');
  assert.equal(result.summary.notJoinedOrLeftDays, 18);
  assert.equal(result.summary.absent, 11);
});

test('holiday beats weekly off and records beat both', () => {
  const result = calendar({
    month: '2028-01',
    today: '2028-01-10',
    holidays: {
      '2028-01-02': 'Sunday holiday',
      '2028-01-03': 'Working day holiday',
      '2028-01-07': 'Recorded holiday',
      '2028-01-09': 'Recorded weekly off',
    },
    weeklyOffDays: [0, 6],
    days: {
      '2028-01-07': { status: 'P' },
      '2028-01-09': { status: 'H' },
    },
  });
  assert.equal(result.days[1]?.status, 'HOLIDAY');
  assert.equal(result.days[1]?.holidayName, 'Sunday holiday');
  assert.equal(result.days[2]?.status, 'HOLIDAY');
  assert.equal(result.days[6]?.status, 'P');
  assert.equal(result.days[8]?.status, 'H');
});

test('today is pending, yesterday is derived absent, and future leave remains recorded', () => {
  const result = calendar({
    month: '2028-02',
    today: '2028-02-15',
    days: { '2028-02-20': { status: 'L' } },
  });
  assert.deepEqual(
    result.days
      .filter((day) => ['2028-02-14', '2028-02-15', '2028-02-20'].includes(day.date))
      .map(({ date, status, derived }) => ({ date, status, derived })),
    [
      { date: '2028-02-14', status: 'A', derived: true },
      { date: '2028-02-15', status: 'PENDING', derived: false },
      { date: '2028-02-20', status: 'L', derived: false },
    ],
  );
  assert.equal(result.summary.absent, 12);
  assert.equal(result.summary.paidLeave, 1);
});

test('counts half-day as half LOP and custom weekly-off days', () => {
  const result = calendar({
    month: '2028-02',
    today: '2028-02-01',
    weeklyOffDays: [0, 6],
    days: {
      '2028-02-01': { status: 'H' },
    },
  });
  assert.equal(result.summary.halfDays, 1);
  assert.equal(result.summary.lop, 0.5);
  assert.equal(result.summary.weeklyOffs, 8);
});

test('ignores stored records outside the employment window', () => {
  const result = calendar({
    month: '2028-02',
    today: '2028-02-29',
    doj: '2028-02-10',
    dol: '2028-02-20',
    days: {
      '2028-02-01': { status: 'P' },
      '2028-02-21': { status: 'P' },
    },
  });
  assert.equal(result.days[0]?.status, 'NOT_JOINED');
  assert.equal(result.days[20]?.status, 'LEFT');
  assert.equal(result.summary.present, 0);
});

test('empty map and summary account for every date exactly once', () => {
  const result = calendar({
    month: '2028-02',
    today: '2028-02-15',
    days: {},
    holidays: {},
    weeklyOffDays: [0],
  });
  const { summary } = result;
  assert.equal(
    summary.weeklyOffs +
      summary.holidays +
      summary.present +
      summary.halfDays +
      summary.absent +
      summary.paidLeave +
      summary.unpaidLeave +
      summary.notJoinedOrLeftDays +
      summary.pending,
    summary.daysInMonth,
  );
  assert.equal(summary.payableDays, summary.daysInMonth - summary.lop);
});
