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
  const updates: Array<{
    uid: string;
    changes: Record<string, unknown>;
    editedBy: string;
  }> = [];
  const operations: EmployeeOperations = {
    createEmployee: async () => {
      calls.push('create');
      return activeEmployee;
    },
    listEmployees: async () => {
      calls.push('list');
      return [activeEmployee];
    },
    getEmployee: async (uid, caller) => {
      calls.push(`get:${uid}`);
      if (caller.role !== 'admin' && caller.uid !== uid) {
        throw new AppError(403, 'FORBIDDEN', 'Employees may only access their own profile.');
      }
      return activeEmployee;
    },
    updateEmployee: async (uid, changes, editedBy) => {
      calls.push('update');
      updates.push({ uid, changes, editedBy });
      if (uid !== 'employee-1') {
        throw new Error('route passed an invalid employee id');
      }
      if (updateError) throw updateError;
      return {
        ...activeEmployee,
        ...changes,
        updatedAt: Timestamp.fromDate(new Date('2026-10-08T10:00:00.000Z')),
        editedBy,
        editedAt: Timestamp.fromDate(new Date('2026-10-08T10:00:00.000Z')),
      };
    },
    addSalaryRevision: async (uid, effectiveFrom, monthlyCtcPaise) => {
      calls.push('add-salary');
      return { empId: uid, effectiveFrom, monthlyCtcPaise };
    },
    listSalaryHistory: async (uid): Promise<SalaryRevision[]> => {
      calls.push('list-salary');
      return [{ empId: uid, effectiveFrom: '2026-10-01', monthlyCtcPaise: 2500000 }];
    },
    deactivateEmployee: async () => {
      calls.push('deactivate');
      return { ...activeEmployee, status: 'inactive' };
    },
    reactivateEmployee: async () => {
      calls.push('reactivate');
      return activeEmployee;
    },
  };

  return {
    calls,
    updates,
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
