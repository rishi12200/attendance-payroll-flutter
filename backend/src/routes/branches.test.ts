import assert from 'node:assert/strict';
import { createServer } from 'node:http';
import test from 'node:test';
import type { DecodedIdToken } from 'firebase-admin/auth';
import { Timestamp } from 'firebase-admin/firestore';
import { createApp } from '../app';
import { AppError } from '../errors/app-error';
import type { BranchRecord } from '../services/branch-service';
import type { EmployeeOperations } from './employees';
import type { BranchOperations } from './branches';

const branchOne: BranchRecord = {
  id: 'branch-1',
  name: 'Chennai Office',
  state: 'Tamil Nadu',
  lat: 13.0827,
  lng: 80.2707,
  radiusMeters: 100,
  status: 'active',
  createdAt: Timestamp.fromDate(new Date('2026-10-01T00:00:00Z')),
  updatedAt: Timestamp.fromDate(new Date('2026-10-01T00:00:00Z')),
};
const branchTwo: BranchRecord = {
  ...branchOne,
  id: 'branch-2',
  name: 'Coimbatore Office',
};

function identity(uid: string, role: string): DecodedIdToken {
  return {
    aud: 'test',
    auth_time: 1,
    exp: 4_000_000_000,
    firebase: { identities: {}, sign_in_provider: 'password' },
    iat: 1,
    iss: 'https://securetoken.google.com/test',
    sub: uid,
    uid,
    role,
  };
}

async function request(
  app: ReturnType<typeof createApp>,
  path: string,
  options: RequestInit = {},
) {
  const server = createServer(app);
  await new Promise<void>((resolve, reject) => {
    server.once('error', reject);
    server.listen(0, '127.0.0.1', resolve);
  });
  const address = server.address();
  if (!address || typeof address === 'string') throw new Error('Test server failed.');
  try {
    const response = await fetch(`http://127.0.0.1:${address.port}${path}`, options);
    return { status: response.status, body: await response.json() };
  } finally {
    await new Promise<void>((resolve, reject) => {
      server.close((error) => (error ? reject(error) : resolve()));
    });
  }
}

function makeApp() {
  const calls: string[] = [];
  const updates: Array<{ id: string; fields: Record<string, unknown>; editor: string }> = [];
  const branches: BranchOperations = {
    createBranch: async (input) => ({ ...branchOne, ...input }),
    listBranches: async (caller, status) => {
      calls.push(`list:${caller.role}:${status}`);
      if (caller.role === 'employee') return [branchOne];
      return [branchOne, branchTwo];
    },
    getBranch: async (id, caller) => {
      calls.push(`get:${id}:${caller.role}`);
      if (caller.role === 'employee' && id !== branchOne.id) {
        throw new AppError(
          403,
          'FORBIDDEN',
          'Employees may only access their active assigned branches.',
        );
      }
      return id === branchOne.id ? branchOne : branchTwo;
    },
    updateBranch: async (id, fields, editor) => {
      calls.push(`update:${id}`);
      updates.push({ id, fields, editor });
      return { ...branchOne, ...fields, id, editedBy: editor };
    },
    deactivateBranch: async (id) => {
      calls.push(`deactivate:${id}`);
      return { ...branchOne, id, status: 'inactive' };
    },
    reactivateBranch: async (id) => {
      calls.push(`reactivate:${id}`);
      return { ...branchOne, id, status: 'active' };
    },
  };
  const employees: EmployeeOperations = {
    createEmployee: async () => ({ ...branchOne, role: 'employee', status: 'active' }),
    listEmployees: async () => [],
    getEmployee: async () => ({
      role: 'employee',
      status: 'active',
      uid: 'employee-1',
    }),
    updateEmployee: async () => ({ ...branchOne, role: 'employee', status: 'active' }),
    addSalaryRevision: async () => ({
      empId: 'employee-1',
      effectiveFrom: '2026-10-01',
      monthlyCtcPaise: 100000,
    }),
    listSalaryHistory: async () => [],
    deactivateEmployee: async () => ({
      ...branchOne,
      role: 'employee',
      status: 'inactive',
    }),
    reactivateEmployee: async () => ({
      ...branchOne,
      role: 'employee',
      status: 'active',
    }),
  };
  return {
    calls,
    updates,
    app: createApp({
      verifyIdToken: async (token) =>
        token === 'employee-token'
          ? identity('employee-1', 'employee')
          : identity('admin-1', 'admin'),
      getProfile: async () => ({
        name: 'Admin',
        email: 'admin@example.com',
        role: 'admin',
        status: 'active',
      }),
      employees,
      branches,
    }),
  };
}

const employeeHeaders = { authorization: 'Bearer employee-token' };
const adminHeaders = { authorization: 'Bearer admin-token' };
const jsonHeaders = { ...adminHeaders, 'content-type': 'application/json' };

test('requires authentication for branch endpoints', async () => {
  const { app } = makeApp();
  const result = await request(app, '/branches');
  assert.equal(result.status, 401);
});

test('employee receives 403 on every admin-only branch route', async () => {
  const { app, calls } = makeApp();
  const requests: Array<{ path: string; method: string; body?: string }> = [
    {
      path: '/branches',
      method: 'POST',
      body: JSON.stringify({
        name: 'Branch',
        state: 'Tamil Nadu',
        lat: 13,
        lng: 80,
        radiusMeters: 100,
      }),
    },
    {
      path: '/branches/branch-1',
      method: 'PATCH',
      body: JSON.stringify({ name: 'Renamed' }),
    },
    { path: '/branches/branch-1/deactivate', method: 'POST' },
    { path: '/branches/branch-1/reactivate', method: 'POST' },
  ];

  for (const item of requests) {
    const result = await request(app, item.path, {
      method: item.method,
      headers: item.body === undefined
        ? employeeHeaders
        : { ...employeeHeaders, 'content-type': 'application/json' },
      body: item.body,
    });
    assert.equal(result.status, 403, `${item.method} ${item.path}`);
  }
  assert.deepEqual(calls, []);
});

test('employee list and details are served through caller-scoped operations', async () => {
  const { app, calls } = makeApp();
  const list = await request(app, '/branches?status=inactive', {
    headers: employeeHeaders,
  });
  assert.equal(list.status, 200);
  assert.deepEqual(list.body.map((branch: BranchRecord) => branch.id), ['branch-1']);

  const allowed = await request(app, '/branches/branch-1', {
    headers: employeeHeaders,
  });
  assert.equal(allowed.status, 200);
  assert.equal(allowed.body.id, 'branch-1');

  const denied = await request(app, '/branches/branch-2', {
    headers: employeeHeaders,
  });
  assert.equal(denied.status, 403);
  assert.deepEqual(calls, [
    'list:employee:inactive',
    'get:branch-1:employee',
    'get:branch-2:employee',
  ]);
});

test('admin can create, list, read, deactivate, and reactivate branches', async () => {
  const { app, calls } = makeApp();
  const create = await request(app, '/branches', {
    method: 'POST',
    headers: jsonHeaders,
    body: JSON.stringify({
      name: 'New Branch',
      state: 'Tamil Nadu',
      lat: 13,
      lng: 80,
      radiusMeters: 100,
    }),
  });
  assert.equal(create.status, 201);
  assert.equal(create.body.status, 'active');
  assert.equal(create.body.createdAt, '2026-10-01T00:00:00.000Z');

  const list = await request(app, '/branches?status=all', {
    headers: adminHeaders,
  });
  assert.equal(list.status, 200);
  assert.equal(list.body.length, 2);

  const detail = await request(app, '/branches/branch-2', {
    headers: adminHeaders,
  });
  assert.equal(detail.status, 200);
  assert.equal(detail.body.name, 'Coimbatore Office');

  const deactivate = await request(app, '/branches/branch-1/deactivate', {
    method: 'POST',
    headers: adminHeaders,
  });
  assert.equal(deactivate.status, 200);
  assert.equal(deactivate.body.status, 'inactive');

  const reactivate = await request(app, '/branches/branch-1/reactivate', {
    method: 'POST',
    headers: adminHeaders,
  });
  assert.equal(reactivate.status, 200);
  assert.equal(reactivate.body.status, 'active');
  assert.deepEqual(calls, [
    'list:admin:all',
    'get:branch-2:admin',
    'deactivate:branch-1',
    'reactivate:branch-1',
  ]);
});

test('branch PATCH preserves validated params with the validated body', async () => {
  const { app, updates } = makeApp();
  const result = await request(app, '/branches/branch-1', {
    method: 'PATCH',
    headers: jsonHeaders,
    body: JSON.stringify({ name: 'Chennai HQ' }),
  });
  assert.equal(result.status, 200);
  assert.deepEqual(updates, [
    { id: 'branch-1', fields: { name: 'Chennai HQ' }, editor: 'admin-1' },
  ]);
  assert.equal(result.body.name, 'Chennai HQ');
  assert.equal(result.body.editedBy, 'admin-1');
});
