import assert from 'node:assert/strict';
import test from 'node:test';
import {
  computeBalances,
  countRequestedDates,
  dayWeight,
  splitByLeaveYear,
  wouldExceedQuota,
} from './leave-quantity';

test('day weights represent full and half-day sessions', () => {
  assert.equal(dayWeight('full'), 1);
  assert.equal(dayWeight('first_half'), 0.5);
  assert.equal(dayWeight('second_half'), 0.5);
});

test('counts only working dates within the employment window', () => {
  assert.deepEqual(countRequestedDates({
    dates: [
      '2026-04-01', // Before joining.
      '2026-04-02',
      '2026-04-03', // Holiday.
      '2026-04-04',
      '2026-04-05', // Sunday.
      '2026-04-06', // After leaving.
    ],
    doj: '2026-04-02',
    dol: '2026-04-05',
    holidayMap: { '2026-04-03': 'Company day' },
    weeklyOffDays: [0],
  }), ['2026-04-02', '2026-04-04']);
});

test('splits requested days across leave years without floating point noise', () => {
  const dates = ['2026-03-31', '2026-04-01', '2026-04-02'];
  assert.deepEqual(splitByLeaveYear(dates, dayWeight('first_half'), 4), [
    {
      yearLabel: 'Apr 2025 - Mar 2026',
      startDate: '2025-04-01',
      endDate: '2026-03-31',
      days: 0.5,
    },
    {
      yearLabel: 'Apr 2026 - Mar 2027',
      startDate: '2026-04-01',
      endDate: '2027-03-31',
      days: 1,
    },
  ]);
  const halfDays = Array.from(
    { length: 15 },
    (_, index) => `2026-05-${String(index + 1).padStart(2, '0')}`,
  );
  assert.equal(splitByLeaveYear(halfDays, 0.5, 1)[0]?.days, 7.5);
});

test('quota compares exact half-day units and allows an exact fit', () => {
  assert.equal(wouldExceedQuota(8, 7, 0.5, 0.5), false);
  assert.equal(wouldExceedQuota(8, 7.5, 0, 1), true);
  assert.equal(wouldExceedQuota(null, 100, 100, 100), false);
  assert.throws(() => wouldExceedQuota(8, 0.25, 0, 0), RangeError);
});

test('computes approved and pending balances from date arrays', () => {
  assert.deepEqual(computeBalances({
    types: [{ id: 'casual', name: 'Casual Leave', annualQuotaDays: 8 }],
    requests: [
      {
        status: 'approved', leaveTypeId: 'casual', session: 'first_half',
        writtenDates: ['2026-01-03', '2026-12-31'],
      },
      {
        status: 'pending', leaveTypeId: 'casual', session: 'second_half',
        requestedDates: ['2026-06-01', '2027-01-01'],
      },
      {
        status: 'cancelled', leaveTypeId: 'casual', writtenDates: ['2026-06-02'],
      },
      {
        status: 'rejected', leaveTypeId: 'casual', requestedDates: ['2026-06-03'],
      },
    ],
    yearStartDate: '2026-01-01',
    yearEndDate: '2026-12-31',
  }), [{
    leaveTypeId: 'casual',
    name: 'Casual Leave',
    quota: 8,
    used: 1,
    pending: 0.5,
    remaining: 6.5,
  }]);
});

test('unlimited quotas have null remaining balances', () => {
  assert.deepEqual(computeBalances({
    types: [{ id: 'unpaid', name: 'Unpaid Leave', annualQuotaDays: null }],
    requests: [{
      status: 'approved', leaveTypeId: 'unpaid', writtenDates: ['2026-02-01'],
    }],
    yearStartDate: '2026-01-01',
    yearEndDate: '2026-12-31',
  }), [{
    leaveTypeId: 'unpaid',
    name: 'Unpaid Leave',
    quota: null,
    used: 1,
    pending: 0,
    remaining: null,
  }]);
});

test('counts legacy approved requests under the fixed legacy type ids', () => {
  const types = [
    { id: 'legacy-paid', name: 'Paid Leave', annualQuotaDays: null },
    { id: 'unpaid', name: 'Unpaid Leave', annualQuotaDays: null },
  ];
  const balances = computeBalances({
    types,
    requests: [
      { status: 'approved', leaveType: 'paid', writtenDates: ['2026-01-01'] },
      { status: 'approved', leaveType: 'unpaid', writtenDates: ['2026-01-02'] },
      { status: 'pending', leaveType: 'paid', requestedDates: ['2026-01-03'] },
    ],
    yearStartDate: '2026-01-01',
    yearEndDate: '2026-12-31',
  });
  assert.equal(balances[0]?.used, 1);
  assert.equal(balances[1]?.used, 1);
  assert.equal(balances[0]?.pending, 0);
});
