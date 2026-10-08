import assert from 'node:assert/strict';
import test from 'node:test';
import {
  leaveApplyBodySchema,
  leaveDecisionBodySchema,
  leaveListQuerySchema,
  leaveMeQuerySchema,
  leaveParamsSchema,
} from './leave-schemas';

test('leave application trims and validates inputs and rejects unknown keys', () => {
  assert.deepEqual(
    leaveApplyBodySchema.parse({
      fromDate: '2026-10-10',
      toDate: '2026-10-12',
      reason: '  Family event  ',
    }),
    { fromDate: '2026-10-10', toDate: '2026-10-12', reason: 'Family event' },
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

test('decision requires leave type only for approvals and limits notes to 200 chars', () => {
  assert.deepEqual(leaveDecisionBodySchema.parse({
    decision: 'approved', leaveType: 'paid', note: '  ok  ',
  }), { decision: 'approved', leaveType: 'paid', note: 'ok' });
  assert.deepEqual(leaveDecisionBodySchema.parse({ decision: 'rejected' }), {
    decision: 'rejected',
  });
  assert.equal(leaveDecisionBodySchema.safeParse({ decision: 'approved' }).success, false);
  assert.equal(leaveDecisionBodySchema.safeParse({ decision: 'rejected', leaveType: 'paid' }).success, false);
  assert.equal(leaveDecisionBodySchema.safeParse({ decision: 'approved', leaveType: 'paid', note: 'x'.repeat(201) }).success, false);
  assert.equal(leaveDecisionBodySchema.safeParse({ decision: 'approved', leaveType: 'paid', surprise: true }).success, false);
});
