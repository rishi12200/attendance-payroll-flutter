import assert from 'node:assert/strict';
import test from 'node:test';
import {
  createEmployeeSchema,
  deactivateEmployeeSchema,
  listEmployeesQuerySchema,
  patchEmployeeSchema,
  salaryRevisionSchema,
} from './employee-schemas';

test('trims create names and normalizes emails to lowercase', () => {
  const result = createEmployeeSchema.parse({
    name: '  Casey Employee  ',
    email: 'CASEY@EXAMPLE.COM',
    tempPassword: 'temporary-123',
    doj: '2026-10-07',
    monthlyCtcPaise: 2500000,
  });
  assert.equal(result.name, 'Casey Employee');
  assert.equal(result.email, 'casey@example.com');
});

test('rejects invalid create values, unknown fields, and floating-point paise', () => {
  const base = {
    name: 'Casey',
    email: 'casey@example.com',
    tempPassword: 'temporary-123',
    doj: '2026-10-07',
    monthlyCtcPaise: 2500000,
  };
  assert.equal(createEmployeeSchema.safeParse({ ...base, monthlyCtcPaise: 10.5 }).success, false);
  assert.equal(createEmployeeSchema.safeParse({ ...base, doj: '2026-02-30' }).success, false);
  assert.equal(createEmployeeSchema.safeParse({ ...base, primaryBranchId: 'branch-1' }).success, false);
  assert.equal(createEmployeeSchema.safeParse({ ...base, email: 'bad-email' }).success, false);
  assert.equal(createEmployeeSchema.safeParse({ ...base, name: '   ' }).success, false);
  assert.equal(createEmployeeSchema.safeParse({ ...base, tempPassword: 'short' }).success, false);
});

test('patch only accepts editable fields and requires at least one change', () => {
  assert.deepEqual(patchEmployeeSchema.parse({ name: ' New Name ' }), { name: 'New Name' });
  assert.equal(patchEmployeeSchema.safeParse({}).success, false);
  assert.equal(patchEmployeeSchema.safeParse({ email: 'new@example.com' }).success, false);
  assert.equal(patchEmployeeSchema.safeParse({ monthlyCtcPaise: 2000 }).success, false);
});

test('validates salary revisions and rejects paise floats', () => {
  assert.equal(
    salaryRevisionSchema.safeParse({
      effectiveFrom: '2026-10-07',
      monthlyCtcPaise: 1200000,
    }).success,
    true,
  );
  assert.equal(
    salaryRevisionSchema.safeParse({
      effectiveFrom: '2026-10-07',
      monthlyCtcPaise: 1.25,
    }).success,
    false,
  );
});

test('validates employee status filter and optional DOL', () => {
  assert.equal(listEmployeesQuerySchema.parse({}).status, 'active');
  assert.equal(listEmployeesQuerySchema.parse({ status: 'all' }).status, 'all');
  assert.equal(listEmployeesQuerySchema.safeParse({ status: 'pending' }).success, false);
  assert.equal(deactivateEmployeeSchema.parse({}).dol, undefined);
  assert.equal(deactivateEmployeeSchema.safeParse({ dol: '2026-15-01' }).success, false);
});
