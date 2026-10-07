import assert from 'node:assert/strict';
import { createServer } from 'node:http';
import test from 'node:test';
import type { DecodedIdToken } from 'firebase-admin/auth';
import { Timestamp } from 'firebase-admin/firestore';
import { createApp } from '../app';
import { AppError } from '../errors/app-error';
import type { EmployeeRecord, SalaryRevision } from '../services/employee-service';
import type { EmployeeOperations } from './employees';

const activeEmployee: EmployeeRecord = {
  uid: 'employee-1',
  empCode: 'EMP001',
  name: 'Test Employee',
  email: 'employee@example.com',
  role: 'employee',
  status: 'active',
  doj: '2026-10-01',
  createdAt: Timestamp.fromDate(new Date('2026-10-07T10:00:00.000Z')),
  designation: 'Associate',
  editedBy: 'admin-1',
  editedAt: Timestamp.fromDate(new Date('2026-10-07T10:00:00.000Z')),
  currentMonthlyCtcPaise: 2500000,
  monthlyCtcPaise: 2500000,
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
  if (!address || typeof address === 'string') {
    throw new Error('Test server did not bind to a TCP port.');
  }
  try {
    const response = await fetch(`http://127.0.0.1:${address.port}${path}`, options);
    return {
      status: response.status,
      body: await response.json(),
    };
  } finally {
    await new Promise<void>((resolve, reject) => {
      server.close((error) => (error ? reject(error) : resolve()));
    });
  }
}

function makeApp(asAdmin = false, updateError?: Error) {
  const calls: string[] = [];
  const salaryAdds: Array<{
    uid: string;
    effectiveFrom: string;
    monthlyCtcPaise: number;
  }> = [];
  const deactivations: Array<{ uid: string; callerUid: string; dol?: string }> = [];
  let employeeState: EmployeeRecord = { ...activeEmployee };
  const updates: Array<{
    uid: string;
    changes: Record<string, unknown>;
    editedBy: string;
  }> = [];
  const operations: EmployeeOperations = {
    createEmployee: async (input) => {
      calls.push('create');
      employeeState = {
        ...activeEmployee,
        name: input.name,
        email: input.email,
      };
      return employeeState;
    },
    listEmployees: async () => {
      calls.push('list');
      return [employeeState];
    },
    getEmployee: async (uid, caller) => {
      calls.push(`get:${uid}`);
      if (caller.role !== 'admin' && caller.uid !== uid) {
        throw new AppError(403, 'FORBIDDEN', 'Employees may only access their own profile.');
      }
      return employeeState;
    },
    updateEmployee: async (uid, changes, editedBy) => {
      calls.push('update');
      updates.push({ uid, changes, editedBy });
      if (uid !== 'employee-1') {
        throw new Error('route passed an invalid employee id');
      }
      if (updateError) throw updateError;
      employeeState = {
        ...employeeState,
        ...changes,
        updatedAt: Timestamp.fromDate(new Date('2026-10-08T10:00:00.000Z')),
        editedBy,
        editedAt: Timestamp.fromDate(new Date('2026-10-08T10:00:00.000Z')),
      };
      return employeeState;
    },
    addSalaryRevision: async (uid, effectiveFrom, monthlyCtcPaise) => {
      calls.push('add-salary');
      salaryAdds.push({ uid, effectiveFrom, monthlyCtcPaise });
      return { empId: uid, effectiveFrom, monthlyCtcPaise };
    },
    listSalaryHistory: async (uid): Promise<SalaryRevision[]> => {
      calls.push('list-salary');
      return [{ empId: uid, effectiveFrom: '2026-10-01', monthlyCtcPaise: 2500000 }];
    },
    deactivateEmployee: async (uid, callerUid, dol) => {
      calls.push('deactivate');
      deactivations.push({ uid, callerUid, dol });
      if (uid !== 'employee-1') {
        throw new Error('route passed an invalid employee id');
      }
      employeeState = {
        ...employeeState,
        status: 'inactive',
        dol: dol ?? '2026-10-07',
        editedBy: 'admin-1',
        editedAt: Timestamp.fromDate(new Date('2026-10-09T10:00:00.000Z')),
        updatedAt: Timestamp.fromDate(new Date('2026-10-09T10:00:00.000Z')),
      };
      return employeeState;
    },
    reactivateEmployee: async () => {
      calls.push('reactivate');
      employeeState = {
        ...employeeState,
        status: 'active',
        dol: null,
        editedBy: 'admin-1',
        editedAt: Timestamp.fromDate(new Date('2026-10-10T10:00:00.000Z')),
        updatedAt: Timestamp.fromDate(new Date('2026-10-10T10:00:00.000Z')),
      };
      return employeeState;
    },
  };

  return {
    calls,
    updates,
    salaryAdds,
    deactivations,
    app: createApp({
      verifyIdToken: async (value) =>
        value === 'employee-token' && !asAdmin
          ? identity('employee-1', 'employee')
          : identity('admin-1', 'admin'),
      getProfile: async () => ({
        name: 'Test',
        email: 'test@example.com',
        role: 'admin',
        status: 'active',
      }),
      employees: operations,
    }),
  };
}

const employeeTokenOptions = {
  headers: { authorization: 'Bearer employee-token' },
};

const jsonHeaders = {
  ...employeeTokenOptions.headers,
  'content-type': 'application/json',
};
const adminTokenOptions = {
  headers: { authorization: 'Bearer admin-token' },
};

test('requires authentication for employee endpoints', async () => {
  const { app } = makeApp();
  const result = await request(app, '/employees');
  assert.equal(result.status, 401);
  assert.deepEqual(result.body, {
    error: {
      code: 'UNAUTHORIZED',
      message: 'A valid Bearer token is required.',
      details: {},
    },
  });
});

test('employee token receives 403 on each admin-only employee endpoint', async () => {
  const { app, calls } = makeApp();
  const endpoints: Array<{ path: string; method: string; body?: string }> = [
    {
      path: '/employees',
      method: 'POST',
      body: JSON.stringify({
        name: 'New Employee',
        email: 'new@example.com',
        tempPassword: 'temporary-123',
        doj: '2026-10-07',
        monthlyCtcPaise: 100000,
      }),
    },
    { path: '/employees', method: 'GET' },
    {
      path: '/employees/employee-1',
      method: 'PATCH',
      body: JSON.stringify({ name: 'Changed' }),
    },
    { path: '/employees/employee-1/salary', method: 'GET' },
    {
      path: '/employees/employee-1/salary',
      method: 'POST',
      body: JSON.stringify({ effectiveFrom: '2026-10-01', monthlyCtcPaise: 100000 }),
    },
    {
      path: '/employees/employee-1/deactivate',
      method: 'POST',
      body: JSON.stringify({}),
    },
    { path: '/employees/employee-1/reactivate', method: 'POST' },
  ];

  for (const endpoint of endpoints) {
    const result = await request(app, endpoint.path, {
      method: endpoint.method,
      headers: endpoint.body === undefined ? employeeTokenOptions.headers : jsonHeaders,
      body: endpoint.body,
    });
    assert.equal(result.status, 403, `${endpoint.method} ${endpoint.path}`);
    assert.deepEqual(result.body, {
      error: {
        code: 'FORBIDDEN',
        message: 'You do not have permission to access this resource.',
        details: {},
      },
    });
  }
  assert.deepEqual(calls, []);
});

test('employee can GET self but not another employee', async () => {
  const { app } = makeApp();
  const own = await request(app, '/employees/employee-1', employeeTokenOptions);
  assert.equal(own.status, 200);
  assert.equal(own.body.uid, 'employee-1');
  assert.equal(own.body.createdAt, '2026-10-07T10:00:00.000Z');
  assert.equal('editedBy' in own.body, false);
  assert.equal('editedAt' in own.body, false);
  assert.equal('currentMonthlyCtcPaise' in own.body, false);
  assert.equal('monthlyCtcPaise' in own.body, false);
  assert.equal(own.body.primaryBranchId, null);
  assert.deepEqual(own.body.allowedBranchIds, []);

  const other = await request(app, '/employees/employee-2', employeeTokenOptions);
  assert.equal(other.status, 403);
  assert.deepEqual(other.body, {
    error: {
      code: 'FORBIDDEN',
      message: 'Employees may only access their own profile.',
      details: {},
    },
  });
});

test('PATCH passes path params and validated body independently', async () => {
  const { app, updates } = makeApp(true);
  const result = await request(app, '/employees/employee-1', {
    method: 'PATCH',
    headers: jsonHeaders,
    body: JSON.stringify({ designation: 'Senior Associate' }),
  });

  assert.equal(result.status, 200);
  assert.deepEqual(updates, [
    {
      uid: 'employee-1',
      changes: { designation: 'Senior Associate' },
      editedBy: 'admin-1',
    },
  ]);
  assert.equal(result.body.designation, 'Senior Associate');
  assert.equal(result.body.name, activeEmployee.name);
  assert.equal(result.body.email, activeEmployee.email);
  assert.equal(result.body.editedBy, 'admin-1');
  assert.equal(result.body.updatedAt, '2026-10-08T10:00:00.000Z');
});

test('employee PATCH accepts branch assignments without losing the path ID', async () => {
  const { app, updates } = makeApp(true);
  const result = await request(app, '/employees/employee-1', {
    method: 'PATCH',
    headers: jsonHeaders,
    body: JSON.stringify({
      primaryBranchId: 'branch-1',
      allowedBranchIds: ['branch-2'],
    }),
  });

  assert.equal(result.status, 200);
  assert.deepEqual(updates, [
    {
      uid: 'employee-1',
      changes: {
        primaryBranchId: 'branch-1',
        allowedBranchIds: ['branch-2'],
      },
      editedBy: 'admin-1',
    },
  ]);
  assert.equal(result.body.primaryBranchId, 'branch-1');
  assert.deepEqual(result.body.allowedBranchIds, ['branch-2']);
});

test('salary and deactivate routes preserve validated params alongside their bodies', async () => {
  const { app, salaryAdds, deactivations } = makeApp(true);

  const salary = await request(app, '/employees/employee-1/salary', {
    method: 'POST',
    headers: jsonHeaders,
    body: JSON.stringify({
      effectiveFrom: '2026-10-03',
      monthlyCtcPaise: 3000000,
    }),
  });
  assert.equal(salary.status, 201);
  assert.deepEqual(salaryAdds, [
    {
      uid: 'employee-1',
      effectiveFrom: '2026-10-03',
      monthlyCtcPaise: 3000000,
    },
  ]);

  const deactivation = await request(app, '/employees/employee-1/deactivate', {
    method: 'POST',
    headers: jsonHeaders,
    body: JSON.stringify({ dol: '2026-10-06' }),
  });
  assert.equal(deactivation.status, 200);
  assert.deepEqual(deactivations, [
    { uid: 'employee-1', callerUid: 'admin-1', dol: '2026-10-06' },
  ]);
});

test('employee write responses match the subsequent admin GET', async () => {
  const { app } = makeApp(true);
  const compareWithGet = async (
    writePath: string,
    method: string,
    body?: Record<string, unknown>,
  ) => {
    const write = await request(app, writePath, {
      method,
      headers: jsonHeaders,
      body: body === undefined ? undefined : JSON.stringify(body),
    });
    assert.equal(write.status, method === 'POST' && writePath === '/employees' ? 201 : 200);
    const get = await request(app, '/employees/employee-1', adminTokenOptions);
    assert.equal(get.status, 200);
    assert.deepEqual(write.body, get.body);
  };

  await compareWithGet('/employees', 'POST', {
    name: 'Created Employee',
    email: 'created@example.com',
    tempPassword: 'temporary-123',
    doj: '2026-10-01',
    monthlyCtcPaise: 2500000,
  });
  await compareWithGet('/employees/employee-1', 'PATCH', {
    designation: 'Senior Associate',
  });
  await compareWithGet('/employees/employee-1/deactivate', 'POST', {});
  await compareWithGet('/employees/employee-1/reactivate', 'POST');
});

test('admin employee list retains the complete employee DTO', async () => {
  const { app } = makeApp(true);
  const result = await request(app, '/employees', adminTokenOptions);

  assert.equal(result.status, 200);
  assert.equal(result.body[0].designation, 'Associate');
  assert.equal(result.body[0].createdAt, '2026-10-07T10:00:00.000Z');
  assert.equal(result.body[0].editedBy, 'admin-1');
  assert.equal(result.body[0].editedAt, '2026-10-07T10:00:00.000Z');
});

test('logs unexpected errors with request metadata and stack, not body data', async () => {
  const { app } = makeApp(true, new Error('Firestore update failed'));
  const originalError = console.error;
  const logged: unknown[][] = [];
  console.error = (...args: unknown[]) => logged.push(args);
  try {
    const result = await request(app, '/employees/employee-1?private=query', {
      method: 'PATCH',
      headers: jsonHeaders,
      body: JSON.stringify({ designation: 'PrivateBodyValue' }),
    });
    assert.equal(result.status, 500);
  } finally {
    console.error = originalError;
  }

  assert.equal(logged.length, 1);
  assert.equal(logged[0][0], 'Unhandled API error');
  assert.deepEqual(logged[0][1], {
    method: 'PATCH',
    path: '/employees/employee-1',
    stack: (logged[0][1] as { stack: string }).stack,
  });
  assert.match((logged[0][1] as { stack: string }).stack, /Firestore update failed/);
  assert.equal(JSON.stringify(logged).includes('PrivateBodyValue'), false);
  assert.equal(JSON.stringify(logged).includes('private=query'), false);
});
