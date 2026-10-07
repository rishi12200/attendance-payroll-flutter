import assert from 'node:assert/strict';
import test from 'node:test';
import { AppError } from '../errors/app-error';
import type { EmployeeRecord } from './employee-service';
import {
  BranchService,
  normalizeEmployeeAssignment,
  validateEmployeeAssignment,
  type BranchRecord,
  type BranchStore,
} from './branch-service';

class FakeBranchStore implements BranchStore {
  readonly branches = new Map<string, BranchRecord>();
  private sequence = 0;

  serverTimestamp() {
    return `timestamp-${++this.sequence}`;
  }

  async listBranches() {
    return [...this.branches.values()];
  }

  async getBranch(id: string) {
    return this.branches.get(id);
  }

  async createBranch(branch: Record<string, unknown>) {
    const id = `branch-${this.branches.size + 1}`;
    this.branches.set(id, { ...branch, id } as BranchRecord);
    return id;
  }

  async updateBranch(id: string, values: Record<string, unknown>) {
    const existing = this.branches.get(id);
    if (!existing) throw new Error('missing branch');
    this.branches.set(id, { ...existing, ...values });
  }
}

class FakeEmployeeStore {
  readonly employees = new Map<string, EmployeeRecord>();

  async listEmployees() {
    return [...this.employees.values()];
  }

  async getEmployee(uid: string) {
    return this.employees.get(uid);
  }
}

function branchInput(name = 'Chennai Office') {
  return {
    name,
    address: 'Example Road',
    state: 'Tamil Nadu',
    lat: 13.0827,
    lng: 80.2707,
    radiusMeters: 100,
  };
}

async function expectAppError(
  promise: Promise<unknown>,
  status: number,
  code: string,
) {
  await assert.rejects(promise, (error: unknown) => {
    assert.ok(error instanceof AppError);
    assert.equal(error.status, status);
    assert.equal(error.code, code);
    return true;
  });
}

test('creates and patches branches using persisted records and audit fields', async () => {
  const branches = new FakeBranchStore();
  const employees = new FakeEmployeeStore();
  const service = new BranchService(branches, employees);
  const created = await service.createBranch(branchInput());

  assert.equal(created.id, 'branch-1');
  assert.equal(created.status, 'active');
  assert.equal(created.createdAt, 'timestamp-1');
  assert.equal(created.updatedAt, 'timestamp-1');
  assert.deepEqual(created, await branches.getBranch(created.id));

  const updated = await service.updateBranch(
    created.id,
    { name: 'Chennai HQ' },
    'admin-1',
  );
  assert.equal(updated.name, 'Chennai HQ');
  assert.equal(updated.editedBy, 'admin-1');
  assert.equal(updated.updatedAt, 'timestamp-2');
  assert.deepEqual(updated, await branches.getBranch(created.id));
});

test('rejects active duplicate names without regard to case', async () => {
  const branches = new FakeBranchStore();
  const service = new BranchService(branches, new FakeEmployeeStore());
  await service.createBranch(branchInput('Chennai Office'));
  await expectAppError(
    service.createBranch(branchInput('  chennai office ')),
    409,
    'BRANCH_NAME_EXISTS',
  );
});

test('filters admin branch lists by requested status', async () => {
  const branches = new FakeBranchStore();
  const service = new BranchService(branches, new FakeEmployeeStore());
  const active = await service.createBranch(branchInput('Active'));
  const inactive = await service.createBranch(branchInput('Inactive'));
  await service.deactivateBranch(inactive.id);

  const caller = { uid: 'admin-1', role: 'admin' };
  assert.deepEqual(
    (await service.listBranches(caller, 'active')).map((branch) => branch.id),
    [active.id],
  );
  assert.deepEqual(
    (await service.listBranches(caller, 'inactive')).map((branch) => branch.id),
    [inactive.id],
  );
  assert.equal((await service.listBranches(caller, 'all')).length, 2);
});

test('blocks branch deactivation while active employees are assigned', async () => {
  const branches = new FakeBranchStore();
  const employees = new FakeEmployeeStore();
  const service = new BranchService(branches, employees);
  const branch = await service.createBranch(branchInput());
  employees.employees.set('employee-1', {
    uid: 'employee-1',
    role: 'employee',
    status: 'active',
    primaryBranchId: branch.id,
  });
  employees.employees.set('employee-2', {
    uid: 'employee-2',
    role: 'employee',
    status: 'active',
    allowedBranchIds: [branch.id],
  });
  employees.employees.set('employee-3', {
    uid: 'employee-3',
    role: 'employee',
    status: 'inactive',
    allowedBranchIds: [branch.id],
  });

  await assert.rejects(service.deactivateBranch(branch.id), (error: unknown) => {
    assert.ok(error instanceof AppError);
    assert.equal(error.status, 409);
    assert.equal(error.details?.activeEmployeeCount, 2);
    assert.match(error.message, /2 active employee/);
    return true;
  });
});

test('deactivates without assignments and reactivates idempotently', async () => {
  const branches = new FakeBranchStore();
  const service = new BranchService(branches, new FakeEmployeeStore());
  const created = await service.createBranch(branchInput());

  const inactive = await service.deactivateBranch(created.id);
  assert.equal(inactive.status, 'inactive');
  assert.deepEqual(inactive, await branches.getBranch(created.id));
  assert.deepEqual(await service.deactivateBranch(created.id), inactive);

  const active = await service.reactivateBranch(created.id);
  assert.equal(active.status, 'active');
  assert.deepEqual(active, await branches.getBranch(created.id));
  assert.deepEqual(await service.reactivateBranch(created.id), active);
});

test('does not reactivate into an active duplicate branch name', async () => {
  const branches = new FakeBranchStore();
  const service = new BranchService(branches, new FakeEmployeeStore());
  const first = await service.createBranch(branchInput('Same Name'));
  const second = await service.createBranch(branchInput('Other Name'));
  await service.deactivateBranch(second.id);
  await service.updateBranch(second.id, { name: 'Same Name' }, 'admin-1');

  await expectAppError(
    service.reactivateBranch(second.id),
    409,
    'BRANCH_NAME_EXISTS',
  );
  assert.equal((await branches.getBranch(second.id))?.status, 'inactive');
  assert.equal(first.status, 'active');
});

test('employee branch list is active and restricted to allowed IDs', async () => {
  const branches = new FakeBranchStore();
  const employees = new FakeEmployeeStore();
  const service = new BranchService(branches, employees);
  const first = await service.createBranch(branchInput('First'));
  const second = await service.createBranch(branchInput('Second'));
  const inactive = await service.createBranch(branchInput('Inactive'));
  await service.deactivateBranch(inactive.id);
  employees.employees.set('employee-1', {
    uid: 'employee-1',
    role: 'employee',
    status: 'active',
    allowedBranchIds: [first.id, inactive.id],
  });

  const result = await service.listBranches(
    { uid: 'employee-1', role: 'employee' },
    'all',
  );
  assert.deepEqual(result.map((item) => item.id), [first.id]);
  assert.ok(second.id);
});

test('normalizes and validates employee assignments', async () => {
  const branches = new FakeBranchStore();
  const employees = new FakeEmployeeStore();
  const service = new BranchService(branches, employees);
  const active = await service.createBranch(branchInput());
  const inactive = await service.createBranch(branchInput('Inactive'));
  await service.deactivateBranch(inactive.id);

  const assignment = normalizeEmployeeAssignment(undefined, {
    primaryBranchId: active.id,
    allowedBranchIds: [],
  });
  assert.deepEqual(assignment, {
    primaryBranchId: active.id,
    allowedBranchIds: [active.id],
  });
  await validateEmployeeAssignment(assignment, branches);

  await expectAppError(
    validateEmployeeAssignment(
      { primaryBranchId: 'missing', allowedBranchIds: [] },
      branches,
    ),
    422,
    'BRANCH_NOT_ASSIGNABLE',
  );
  await expectAppError(
    validateEmployeeAssignment(
      { primaryBranchId: inactive.id, allowedBranchIds: [inactive.id] },
      branches,
    ),
    422,
    'BRANCH_NOT_ASSIGNABLE',
  );

  await assert.rejects(
    Promise.resolve().then(() =>
      normalizeEmployeeAssignment(undefined, {
        primaryBranchId: null,
        allowedBranchIds: [active.id, active.id],
      }),
    ),
    (error: unknown) =>
      error instanceof AppError && error.code === 'DUPLICATE_BRANCH_ASSIGNMENT',
  );
  await assert.rejects(
    Promise.resolve().then(() =>
      normalizeEmployeeAssignment(undefined, {
        primaryBranchId: 'primary',
        allowedBranchIds: Array.from({ length: 20 }, (_, index) => `branch-${index}`),
      }),
    ),
    (error: unknown) =>
      error instanceof AppError && error.code === 'TOO_MANY_BRANCH_ASSIGNMENTS',
  );
  assert.deepEqual(
    normalizeEmployeeAssignment(
      { role: 'employee', status: 'active' },
      { primaryBranchId: null, allowedBranchIds: [] },
    ),
    { primaryBranchId: null, allowedBranchIds: [] },
  );
});
