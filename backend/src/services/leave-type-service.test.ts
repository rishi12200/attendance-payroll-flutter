import assert from 'node:assert/strict';
import test from 'node:test';
import { AppError } from '../errors/app-error';
import {
  LeaveTypeService,
  type LeaveTypeRecord,
  type LeaveTypeStore,
} from './leave-type-service';

class FakeLeaveTypeStore implements LeaveTypeStore {
  readonly values = new Map<string, LeaveTypeRecord>();
  readonly audits: Array<{ action: string; before?: LeaveTypeRecord; after: LeaveTypeRecord }> = [];
  pending = 0;
  sequence = 0;

  serverTimestamp() { return '2026-10-14T00:00:00.000Z'; }
  async listLeaveTypes() { return [...this.values.values()].map((value) => ({ ...value })); }
  async getLeaveType(id: string) { const value = this.values.get(id); return value && { ...value }; }
  async countPendingRequests() { return this.pending; }
  async writeLeaveType(input: {
    id: string; before?: LeaveTypeRecord; after: LeaveTypeRecord;
    action: 'leaveType.create' | 'leaveType.update' | 'leaveType.deactivate' | 'leaveType.reactivate';
    by: string; createOnly: boolean;
  }) {
    this.values.set(input.id, { ...input.after });
    this.audits.push({ action: input.action, before: input.before, after: { ...input.after } });
  }
}

function seeded(id: string, name: string, code: string, patch: Partial<LeaveTypeRecord> = {}): LeaveTypeRecord {
  return {
    id, name, code, paid: true, annualQuotaDays: 10, allowHalfDay: true,
    status: 'active', system: false, sortOrder: 1, ...patch,
  };
}

function errorCode(error: unknown): string | undefined {
  return error instanceof AppError ? error.code : undefined;
}

test('lists employee types trimmed and sorted, while admins receive inactive and legacy types', async () => {
  const store = new FakeLeaveTypeStore();
  store.values.set('casual', seeded('casual', 'Casual Leave', 'CL', { sortOrder: 2 }));
  store.values.set('annual', seeded('annual', 'Annual Leave', 'AL', { sortOrder: 1 }));
  store.values.set('legacy-paid', seeded('legacy-paid', 'Paid Leave (legacy)', 'PL', { status: 'inactive', system: true }));
  const service = new LeaveTypeService(store);
  assert.deepEqual(await service.list({ role: 'employee' }), [
    { id: 'annual', name: 'Annual Leave', code: 'AL', paid: true, allowHalfDay: true, annualQuotaDays: 10 },
    { id: 'casual', name: 'Casual Leave', code: 'CL', paid: true, allowHalfDay: true, annualQuotaDays: 10 },
  ]);
  assert.equal((await service.list({ role: 'admin' })).length, 3);
  assert.equal((await service.list({ role: 'admin' }, 'active')).length, 2);
});

test('rejects case-insensitive duplicate names and codes across every type', async () => {
  const store = new FakeLeaveTypeStore();
  store.values.set('a', seeded('a', 'Annual Leave', 'AL', { status: 'inactive' }));
  const service = new LeaveTypeService(store);
  assert.equal(errorCode(await service.create({ name: ' annual leave ', code: 'AN', paid: true, annualQuotaDays: 1, allowHalfDay: true }, 'admin').catch((error) => error)), 'LEAVE_TYPE_NAME_EXISTS');
  assert.equal(errorCode(await service.create({ name: 'Other', code: 'al', paid: true, annualQuotaDays: 1, allowHalfDay: true }, 'admin').catch((error) => error)), 'LEAVE_TYPE_CODE_EXISTS');
});

test('writes create and update audits with before and after values', async () => {
  const store = new FakeLeaveTypeStore();
  const service = new LeaveTypeService(store);
  const created = await service.create({ name: 'Flex Leave', code: 'FL', paid: true, annualQuotaDays: 2.5, allowHalfDay: false }, 'admin');
  const id = String(created.id);
  await service.update(id, { sortOrder: 8 }, 'admin');
  assert.equal(store.audits[0]?.action, 'leaveType.create');
  assert.equal(store.audits[1]?.action, 'leaveType.update');
  assert.equal(store.audits[1]?.before?.sortOrder, 0);
  assert.equal(store.audits[1]?.after.sortOrder, 8);
});

test('enforces system rules and blocks deactivation with pending requests', async () => {
  const store = new FakeLeaveTypeStore();
  store.values.set('unpaid', seeded('unpaid', 'Unpaid Leave', 'UL', { paid: false, annualQuotaDays: null, system: true }));
  store.values.set('legacy-paid', seeded('legacy-paid', 'Paid Leave (legacy)', 'PL', { system: true, status: 'inactive', annualQuotaDays: null }));
  store.values.set('annual', seeded('annual', 'Annual Leave', 'AL'));
  const service = new LeaveTypeService(store);
  assert.equal(errorCode(await service.update('unpaid', { paid: true }, 'admin').catch((error) => error)), 'SYSTEM_LEAVE_TYPE');
  assert.equal(errorCode(await service.deactivate('unpaid', 'admin').catch((error) => error)), 'SYSTEM_LEAVE_TYPE');
  assert.equal(errorCode(await service.reactivate('legacy-paid', 'admin').catch((error) => error)), 'SYSTEM_LEAVE_TYPE');
  store.pending = 2;
  const error = await service.deactivate('annual', 'admin').catch((value) => value);
  assert.equal(errorCode(error), 'LEAVE_TYPE_IN_USE');
  assert.deepEqual((error as AppError).details, { pendingCount: 2 });
  store.pending = 0;
  assert.equal((await service.deactivate('annual', 'admin')).status, 'inactive');
  assert.equal((await service.deactivate('annual', 'admin')).status, 'inactive');
});
