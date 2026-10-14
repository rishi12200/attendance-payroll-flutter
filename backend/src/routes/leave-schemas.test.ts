import assert from 'node:assert/strict';
import test from 'node:test';
import {
  leaveApplyBodySchema,
  leaveBalanceQuerySchema,
  leaveDecisionBodySchema,
  leaveListQuerySchema,
  leaveMeQuerySchema,
  leaveParamsSchema,
} from './leave-schemas';

test('leave application trims and validates inputs and rejects unknown keys', () => {
  assert.deepEqual(
    leaveApplyBodySchema.parse({
      leaveTypeId: 'annual',
      fromDate: '2026-10-10',
      toDate: '2026-10-12',
      reason: '  Family event  ',
    }),
    { leaveTypeId: 'annual', fromDate: '2026-10-10', toDate: '2026-10-12', reason: 'Family event', session: 'full' },
  );
  assert.equal(leaveApplyBodySchema.safeParse({
    fromDate: '2026-02-30', toDate: '2026-03-01', reason: 'x',
  }).success, false);
  assert.equal(leaveApplyBodySchema.safeParse({
    fromDate: '2026-10-10', toDate: '2026-10-10', reason: ' ',
  }).success, false);
  assert.equal(leaveApplyBodySchema.safeParse({
    fromDate: '2026-10-10', toDate: '2026-10-10', reason: 'x', extra: true,
  }).success, false);
});

test('leave status queries and IDs are validated strictly', () => {
  assert.deepEqual(leaveListQuerySchema.parse({}), { status: 'pending' });
  assert.deepEqual(leaveListQuerySchema.parse({ status: 'all', empId: 'emp-1' }), {
    status: 'all', empId: 'emp-1',
  });
  assert.equal(leaveMeQuerySchema.safeParse({ status: 'unknown' }).success, false);
  assert.equal(leaveParamsSchema.safeParse({ id: '  ' }).success, false);
});

test('leave balance query validates optional year and employee id', () => {
  assert.deepEqual(leaveBalanceQuerySchema.parse({ year: '2025', empId: ' emp-1 ' }), {
    year: 2025, empId: 'emp-1',
  });
  assert.equal(leaveBalanceQuerySchema.safeParse({ year: '1999' }).success, false);
  assert.equal(leaveBalanceQuerySchema.safeParse({ year: 'not-a-year' }).success, false);
  assert.equal(leaveBalanceQuerySchema.safeParse({ extra: 'x' }).success, false);
});

test('decision accepts only the decision and optional note', () => {
  assert.deepEqual(leaveDecisionBodySchema.parse({
    decision: 'approved', note: '  ok  ',
  }), { decision: 'approved', note: 'ok' });
  assert.deepEqual(leaveDecisionBodySchema.parse({ decision: 'rejected' }), {
    decision: 'rejected',
  });
  assert.equal(leaveDecisionBodySchema.safeParse({ decision: 'approved', leaveType: 'paid' }).success, false);
  assert.equal(leaveDecisionBodySchema.safeParse({ decision: 'rejected', leaveType: 'paid' }).success, false);
  assert.equal(leaveDecisionBodySchema.safeParse({ decision: 'approved', note: 'x'.repeat(201) }).success, false);
  assert.equal(leaveDecisionBodySchema.safeParse({ decision: 'approved', surprise: true }).success, false);
});
