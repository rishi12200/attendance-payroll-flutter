import assert from 'node:assert/strict';
import { createServer } from 'node:http';
import test from 'node:test';
import { Timestamp } from 'firebase-admin/firestore';
import type { DecodedIdToken } from 'firebase-admin/auth';
import { createApp } from '../app';
import type { LeaveOperations } from './leaves';

function identity(uid: string, role: string): DecodedIdToken {
  return {
    aud: 'test', auth_time: 1, exp: 4_000_000_000,
    firebase: { identities: {}, sign_in_provider: 'password' },
    iat: 1, iss: 'https://securetoken.google.com/test', sub: uid, uid, role,
  };
}

async function request(app: ReturnType<typeof createApp>, path: string, options: RequestInit = {}) {
  const server = createServer(app);
  await new Promise<void>((resolve, reject) => {
    server.once('error', reject);
    server.listen(0, '127.0.0.1', resolve);
  });
  const address = server.address();
  if (!address || typeof address === 'string') throw new Error('Test server failed to bind.');
  try {
    const response = await fetch(`http://127.0.0.1:${address.port}${path}`, options);
    const body = await response.text();
    return { status: response.status, body: body === '' ? undefined : JSON.parse(body) };
  } finally {
    await new Promise<void>((resolve, reject) => {
      server.close((error) => error ? reject(error) : resolve());
    });
  }
}

const headers = { authorization: 'Bearer admin-token', 'content-type': 'application/json' };
const employeeHeaders = { ...headers, authorization: 'Bearer employee-token' };

function makeApp() {
  const calls: string[] = [];
  const requestRecord: Record<string, unknown> = {
    id: 'leave-1', empId: 'emp-1', fromDate: '2026-10-10', toDate: '2026-10-11',
    reason: 'personal', status: 'pending',
    createdAt: Timestamp.fromDate(new Date('2026-10-08T10:00:00Z')),
    updatedAt: Timestamp.fromDate(new Date('2026-10-08T10:00:00Z')),
  };
  const leaves: LeaveOperations = {
    apply: async (caller, body) => {
      calls.push(`apply:${caller.uid}:${body.reason}`);
      Object.assign(requestRecord, { fromDate: body.fromDate, toDate: body.toDate, reason: body.reason, status: 'pending' });
      return { ...requestRecord };
    },
    listMine: async (_caller, status) => { calls.push(`mine:${status ?? ''}`); return [{ ...requestRecord }]; },
    listAll: async (_caller, input) => { calls.push(`list:${input.status}:${input.empId ?? ''}`); return [{ ...requestRecord, empCode: 'EMP001', name: 'Asha', designation: 'Associate' }]; },
    getById: async (_caller, id) => { calls.push(`get:${id}`); return { ...requestRecord }; },
    cancel: async (_caller, id) => {
      calls.push(`cancel:${id}`);
      requestRecord.status = 'cancelled';
      return { ...requestRecord };
    },
    decide: async ({ id, decision, leaveType }) => {
      calls.push(`decision:${id}:${decision}:${leaveType ?? ''}`);
      Object.assign(requestRecord, {
        status: decision, decidedBy: 'admin-1', decidedAt: Timestamp.fromDate(new Date('2026-10-08T10:00:00Z')),
        decisionNote: null,
        ...(decision === 'approved' ? { leaveType, writtenDates: ['2026-10-10', '2026-10-11'], skippedDates: [] } : {}),
      });
      return { ...requestRecord };
    },
  };
  const app = createApp({
    verifyIdToken: async (token) => token === 'employee-token'
      ? identity('emp-1', 'employee')
      : identity('admin-1', 'admin'),
    getProfile: async () => undefined,
    leaves,
  });
  return { app, calls };
}

test('leave routes enforce bearer authentication and endpoint roles', async () => {
  const { app } = makeApp();
  const endpoints: Array<[string, RequestInit | undefined, number]> = [
    ['/leaves', { method: 'POST', headers, body: JSON.stringify({ fromDate: '2026-10-10', toDate: '2026-10-10', reason: 'x' }) }, 403],
    ['/leaves/me', { headers }, 403],
    ['/leaves/leave-1/cancel', { method: 'POST', headers }, 403],
    ['/leaves?status=pending', { headers: employeeHeaders }, 403],
    ['/leaves/leave-1', { headers }, 200],
    ['/leaves/leave-1/decision', { method: 'POST', headers: employeeHeaders, body: JSON.stringify({ decision: 'rejected' }) }, 403],
  ];
  for (const [path, options, authenticatedStatus] of endpoints) {
    const noTokenHeaders = new Headers(options?.headers);
    noTokenHeaders.delete('authorization');
    assert.equal((await request(app, path, { ...options, headers: noTokenHeaders })).status, 401, path);
    assert.equal((await request(app, path, options)).status, authenticatedStatus, path);
  }

  assert.equal((await request(app, '/leaves', {
    method: 'POST', headers: employeeHeaders,
    body: JSON.stringify({ fromDate: '2026-10-10', toDate: '2026-10-10', reason: 'x' }),
  })).status, 201);
  assert.equal((await request(app, '/leaves/me', { headers: employeeHeaders })).status, 200);
  assert.equal((await request(app, '/leaves/leave-1', { headers: employeeHeaders })).status, 200);
  assert.equal((await request(app, '/leaves/leave-1/cancel', { method: 'POST', headers: employeeHeaders })).status, 200);
  assert.equal((await request(app, '/leaves?status=all&empId=emp-1', { headers })).status, 200);
  assert.equal((await request(app, '/leaves/leave-1/decision', {
    method: 'POST', headers, body: JSON.stringify({ decision: 'approved', leaveType: 'paid' }),
  })).status, 200);
});

test('leave routes validate each request part and serialize returned timestamps', async () => {
  const { app, calls } = makeApp();
  const invalid: Array<[string, RequestInit?]> = [
    ['/leaves', { method: 'POST', headers: employeeHeaders, body: JSON.stringify({ fromDate: '2026-02-30', toDate: '2026-03-01', reason: 'x' }) }],
    ['/leaves', { method: 'POST', headers: employeeHeaders, body: JSON.stringify({ fromDate: '2026-10-10', toDate: '2026-10-10', reason: 'x', extra: true }) }],
    ['/leaves/me?status=unknown', { headers: employeeHeaders }],
    ['/leaves?status=unknown', { headers }],
    ['/leaves?extra=x', { headers }],
    ['/leaves/leave-1/decision', { method: 'POST', headers, body: JSON.stringify({ decision: 'approved' }) }],
    ['/leaves/leave-1/decision', { method: 'POST', headers, body: JSON.stringify({ decision: 'rejected', leaveType: 'paid' }) }],
    ['/leaves/leave-1/decision', { method: 'POST', headers, body: JSON.stringify({ decision: 'approved', leaveType: 'paid', unknown: true }) }],
  ];
  for (const [path, options] of invalid) {
    const result = await request(app, path, options);
    assert.equal(result.status, 400, path);
    assert.equal(result.body.error.code, 'VALIDATION_ERROR');
  }

  const created = await request(app, '/leaves', {
    method: 'POST', headers: employeeHeaders,
    body: JSON.stringify({ fromDate: '2026-10-10', toDate: '2026-10-10', reason: '  personal  ' }),
  });
  assert.equal(created.status, 201);
  assert.equal(created.body.createdAt, '2026-10-08T10:00:00.000Z');
  assert.equal(created.body.fromDate, '2026-10-10');
  assert.equal(created.body.toDate, '2026-10-10');
  const subsequentGet = await request(app, '/leaves/leave-1', { headers: employeeHeaders });
  assert.deepEqual(created.body, subsequentGet.body);

  const mine = await request(app, '/leaves/me', { headers: employeeHeaders });
  const adminList = await request(app, '/leaves?status=all', { headers });
  assert.equal(mine.body[0].fromDate, '2026-10-10');
  assert.equal(mine.body[0].toDate, '2026-10-10');
  assert.equal(adminList.body[0].fromDate, '2026-10-10');
  assert.equal(adminList.body[0].toDate, '2026-10-10');
  assert.equal(adminList.body[0].empCode, 'EMP001');

  const cancelled = await request(app, '/leaves/leave-1/cancel', { method: 'POST', headers: employeeHeaders });
  const cancelledGet = await request(app, '/leaves/leave-1', { headers: employeeHeaders });
  assert.equal(cancelled.body.fromDate, '2026-10-10');
  assert.equal(cancelled.body.toDate, '2026-10-10');
  assert.deepEqual(cancelled.body, cancelledGet.body);

  const decided = await request(app, '/leaves/leave-1/decision', {
    method: 'POST', headers, body: JSON.stringify({ decision: 'approved', leaveType: 'paid' }),
  });
  const decidedGet = await request(app, '/leaves/leave-1', { headers });
  assert.equal(decided.body.fromDate, '2026-10-10');
  assert.equal(decided.body.toDate, '2026-10-10');
  assert.deepEqual(decided.body, decidedGet.body);
  assert.deepEqual(calls, [
    'apply:emp-1:personal', 'get:leave-1', 'mine:', 'list:all:',
    'cancel:leave-1', 'get:leave-1', 'decision:leave-1:approved:paid', 'get:leave-1',
  ]);
});
