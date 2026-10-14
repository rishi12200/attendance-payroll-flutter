import assert from 'node:assert/strict';
import test from 'node:test';
import { leaveTypeCreateBodySchema, leaveTypePatchBodySchema } from './leave-type-schemas';

test('leave type bodies trim names and enforce quota and field bounds', () => {
  assert.deepEqual(leaveTypeCreateBodySchema.parse({
    name: ' Annual Leave ', code: 'AL', paid: true, annualQuotaDays: 18,
    allowHalfDay: true,
  }), {
    name: 'Annual Leave', code: 'AL', paid: true, annualQuotaDays: 18,
    allowHalfDay: true,
  });
  for (const quota of [0, 0.25, 366.5]) {
    assert.equal(leaveTypeCreateBodySchema.safeParse({
      name: 'Valid', code: 'V', paid: true, annualQuotaDays: quota, allowHalfDay: false,
    }).success, false);
  }
  assert.equal(leaveTypeCreateBodySchema.safeParse({
    name: 'Valid', code: 'lower', paid: true, annualQuotaDays: null, allowHalfDay: false,
  }).success, false);
  assert.equal(leaveTypeCreateBodySchema.safeParse({
    name: 'Valid', code: 'V', paid: true, annualQuotaDays: null, allowHalfDay: false, extra: 1,
  }).success, false);
  assert.equal(leaveTypePatchBodySchema.safeParse({}).success, false);
  assert.equal(leaveTypePatchBodySchema.safeParse({ name: 'x'.repeat(51) }).success, false);
});
