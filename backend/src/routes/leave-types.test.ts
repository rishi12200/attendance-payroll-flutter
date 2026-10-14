import assert from 'node:assert/strict';
import { createServer } from 'node:http';
import test from 'node:test';
import type { DecodedIdToken } from 'firebase-admin/auth';
import { createApp } from '../app';
import type { LeaveTypeOperations } from './leave-types';

function identity(uid: string, role: string): DecodedIdToken {
  return {
    aud: 'test', auth_time: 1, exp: 4_000_000_000,
    firebase: { identities: {}, sign_in_provider: 'password' }, iat: 1,
    iss: 'https://securetoken.google.com/test', sub: uid, uid, role,
  };
}

async function request(app: ReturnType<typeof createApp>, path: string, options: RequestInit = {}) {
  const server = createServer(app);
  await new Promise<void>((resolve) => server.listen(0, '127.0.0.1', resolve));
  const address = server.address();
  if (!address || typeof address === 'string') throw new Error('Test server failed.');
  try {
    const response = await fetch(`http://127.0.0.1:${address.port}${path}`, options);
    return { status: response.status, body: await response.json() };
  } finally {
    await new Promise<void>((resolve, reject) => server.close((error) => error ? reject(error) : resolve()));
  }
}

function setup() {
  const calls: string[] = [];
  const leaveTypes: LeaveTypeOperations = {
    list: async (_caller, status) => { calls.push(`list:${status}`); return []; },
    create: async (input, by) => { calls.push(`create:${by}`); return { ...input, id: 'new' }; },
    update: async (id, _changes, by) => { calls.push(`update:${id}:${by}`); return { id }; },
    deactivate: async (id) => { calls.push(`deactivate:${id}`); return { id, status: 'inactive' }; },
    reactivate: async (id) => { calls.push(`reactivate:${id}`); return { id, status: 'active' }; },
  };
  return {
    calls,
    app: createApp({
      verifyIdToken: async (token) => token === 'employee-token'
        ? identity('employee-1', 'employee') : identity('admin-1', 'admin'),
      getProfile: async () => ({ name: 'Admin', email: 'admin@example.com', role: 'admin', status: 'active' }),
      leaveTypes,
    }),
  };
}

test('leave type routes require auth and restrict all mutations to admins', async () => {
  const { app, calls } = setup();
  assert.equal((await request(app, '/leave-types')).status, 401);
  const headers = { authorization: 'Bearer employee-token', 'content-type': 'application/json' };
  const actions: Array<[string, string, string?]> = [
    ['POST', '/leave-types', JSON.stringify({ name: 'Annual', code: 'AL', paid: true, annualQuotaDays: 2, allowHalfDay: true })],
    ['PATCH', '/leave-types/a', JSON.stringify({ name: 'Edited' })],
    ['POST', '/leave-types/a/deactivate'],
    ['POST', '/leave-types/a/reactivate'],
  ];
  for (const [method, path, body] of actions) {
    assert.equal((await request(app, path, { method, headers, body })).status, 403, `${method} ${path}`);
  }
  assert.deepEqual(calls, []);
});

test('leave type routes validate strictly and dispatch authenticated admin operations', async () => {
  const { app, calls } = setup();
  const headers = { authorization: 'Bearer admin-token', 'content-type': 'application/json' };
  assert.equal((await request(app, '/leave-types', { headers })).status, 200);
  assert.equal((await request(app, '/leave-types', { method: 'POST', headers, body: '{"name":"bad"}' })).status, 400);
  assert.equal((await request(app, '/leave-types?status=nope', { headers })).status, 400);
  const create = await request(app, '/leave-types', {
    method: 'POST', headers,
    body: JSON.stringify({ name: 'Annual', code: 'AL', paid: true, annualQuotaDays: 18, allowHalfDay: true }),
  });
  assert.equal(create.status, 201);
  assert.equal(create.body.id, 'new');
  assert.equal((await request(app, '/leave-types/a', { method: 'PATCH', headers, body: JSON.stringify({ name: 'Edited' }) })).status, 200);
  assert.equal((await request(app, '/leave-types/a/deactivate', { method: 'POST', headers })).status, 200);
  assert.equal((await request(app, '/leave-types/a/reactivate', { method: 'POST', headers })).status, 200);
  assert.deepEqual(calls, ['list:all', 'create:admin-1', 'update:a:admin-1', 'deactivate:a', 'reactivate:a']);
});
