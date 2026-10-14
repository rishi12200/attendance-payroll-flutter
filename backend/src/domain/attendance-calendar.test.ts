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
    },
    weeklyOffDays: [0, 6],
    days: {
      '2028-01-07': { status: 'P' },
      '2028-01-08': { status: 'H' },
    },
  });
  assert.equal(result.days[1]?.status, 'HOLIDAY');
  assert.equal(result.days[1]?.holidayName, 'Sunday holiday');
  assert.equal(result.days[2]?.status, 'HOLIDAY');
  assert.equal(result.days[6]?.status, 'P');
  assert.equal(result.days[6]?.holidayName, 'Recorded holiday');
  assert.equal(result.days[7]?.status, 'H');
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

test('calendar includes the leave request id and summarizes paid and unpaid leave', () => {
  const result = calendar({
    month: '2028-02',
    today: '2028-02-01',
    weeklyOffDays: [],
    days: {
      '2028-02-01': {
        status: 'L',
        source: 'leave',
        leaveRequestId: 'leave-paid',
      },
      '2028-02-02': {
        status: 'UL',
        source: 'leave',
        leaveRequestId: 'leave-unpaid',
      },
    },
  });
  assert.equal(result.days[0]?.leaveRequestId, 'leave-paid');
  assert.equal(result.days[1]?.leaveRequestId, 'leave-unpaid');
  assert.equal(result.summary.paidLeave, 1);
  assert.equal(result.summary.unpaidLeave, 1);
  assert.equal(result.summary.lop, 1);
});

test('classifies half-leave rows, preserves day details, and splits the summary in halves', () => {
  const entries = [
    { date: '2028-02-01', marker: { session: 'first_half', paid: true, leaveTypeId: 'annual', leaveRequestId: 'r1' }, status: 'P', inTime: '09:00' },
    { date: '2028-02-02', marker: { session: 'second_half', paid: true, leaveTypeId: 'annual', leaveRequestId: 'r2' } },
    { date: '2028-02-03', marker: { session: 'first_half', paid: false, leaveTypeId: 'unpaid', leaveRequestId: 'r3' }, status: 'P' },
    { date: '2028-02-04', marker: { session: 'second_half', paid: false, leaveTypeId: 'unpaid', leaveRequestId: 'r4' } },
    { date: '2028-02-15', marker: { session: 'first_half', paid: true, leaveTypeId: 'annual', leaveRequestId: 'r5' } },
    { date: '2028-02-05', marker: { session: 'first_half', paid: true, leaveTypeId: 'annual', leaveRequestId: 'r6' }, status: 'A' },
  ];
  const monthDays = Array.from({ length: 29 }, (_, index) => [
    `2028-02-${String(index + 1).padStart(2, '0')}`,
    { status: 'P' },
  ]);
  const days = Object.fromEntries([...monthDays, ...entries.map((row) => [row.date, {
    ...(row.status === undefined ? {} : { status: row.status }),
    halfLeave: row.marker,
    ...(row.inTime === undefined ? {} : { inTime: row.inTime }),
  }])]);
  const result = calendar({
    today: '2028-02-15',
    weeklyOffDays: [],
    days,
    leaveTypeNames: { annual: 'Annual Leave', unpaid: 'Unpaid Leave' },
  });
  assert.deepEqual(result.days.slice(0, 4).map((day) => [day.status, day.otherHalf]), [
    ['HL', 'present'], ['HL', 'absent'], ['HL', 'present'], ['HL', 'absent'],
  ]);
  assert.equal(result.days[14]?.otherHalf, 'pending');
  assert.deepEqual(result.days[0]?.halfLeave, {
    session: 'first_half', paid: true, leaveTypeId: 'annual',
    leaveTypeName: 'Annual Leave', leaveRequestId: 'r1',
  });
  assert.equal(result.days[0]?.inTime, '09:00');
  assert.equal(result.summary.paidLeave, 2);
  assert.equal(result.summary.unpaidLeave, 1);
  assert.equal(result.summary.present, 24);
  assert.equal(result.summary.absent, 1.5);
  assert.equal(result.summary.pending, 0.5);
  assert.equal(result.summary.lop, 2.5);
});

test('stored H, L and UL statuses win over half-leave markers', () => {
  const result = calendar({
    today: '2028-02-01',
    weeklyOffDays: [],
    days: Object.fromEntries(['H', 'L', 'UL'].map((status, index) => [
      `2028-02-0${index + 1}`,
      { status, halfLeave: { session: 'first_half', paid: true, leaveTypeId: 'annual', leaveRequestId: 'r' } },
    ])),
  });
  assert.deepEqual(result.days.slice(0, 3).map((day) => day.status), ['H', 'L', 'UL']);
  assert.equal(result.summary.paidLeave, 1);
  assert.equal(result.summary.unpaidLeave, 1);
  assert.equal(result.summary.halfDays, 1);
});

test('ignores marker-only days outside employment and honors them on holidays', () => {
  const marker = { session: 'first_half', paid: true, leaveTypeId: 'annual', leaveRequestId: 'r' };
  const result = calendar({
    today: '2028-02-20',
    doj: '2028-02-02',
    holidays: { '2028-02-03': 'Holiday' },
    weeklyOffDays: [],
    days: { '2028-02-01': { halfLeave: marker }, '2028-02-03': { halfLeave: marker } },
  });
  assert.equal(result.days[0]?.status, 'NOT_JOINED');
  assert.equal(result.days[2]?.status, 'HL');
});

test('summary total remains one day per date for half markers in all month lengths', () => {
  for (const month of ['2027-02', '2028-02', '2028-01', '2028-04']) {
    const count = new Date(Date.UTC(Number(month.slice(0, 4)), Number(month.slice(5),), 0)).getUTCDate();
    const days = Object.fromEntries(Array.from({ length: count }, (_, index) => {
      const date = `${month}-${String(index + 1).padStart(2, '0')}`;
      return [date, { halfLeave: {
        session: 'first_half', paid: index % 2 === 0,
        leaveTypeId: index % 2 === 0 ? 'annual' : 'unpaid', leaveRequestId: `r${index}`,
      } }];
    }));
    const result = calendar({ month, today: `${month}-01`, weeklyOffDays: [], days });
    const summary = result.summary;
    assert.equal(
      summary.weeklyOffs + summary.holidays + summary.present + summary.halfDays +
        summary.absent + summary.paidLeave + summary.unpaidLeave +
        summary.notJoinedOrLeftDays + summary.pending,
      summary.daysInMonth,
    );
  }
});
