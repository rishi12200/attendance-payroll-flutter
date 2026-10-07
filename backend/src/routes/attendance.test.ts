import assert from 'node:assert/strict';
import { createServer } from 'node:http';
import test from 'node:test';
import type { DecodedIdToken } from 'firebase-admin/auth';
import { Timestamp } from 'firebase-admin/firestore';
import { createApp } from '../app';
import type { AttendanceOperations } from './attendance';

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
  if (!address || typeof address === 'string') throw new Error('Test server failed to bind.');
  try {
    const response = await fetch(`http://127.0.0.1:${address.port}${path}`, options);
    return { status: response.status, body: await response.json() };
  } finally {
    await new Promise<void>((resolve, reject) => {
      server.close((error) => (error ? reject(error) : resolve()));
    });
  }
}

function makeApp(role: 'admin' | 'employee' = 'employee') {
  const calls: string[] = [];
  const attendance: AttendanceOperations = {
    checkIn: async (caller, body) => {
      calls.push(`in:${caller.uid}:${body.deviceId}`);
      return { date: '2026-10-10', status: 'P', inTime: Timestamp.fromDate(new Date('2026-10-10T10:00:00Z')) };
    },
    checkOut: async (caller, body) => {
      calls.push(`out:${caller.uid}:${body.deviceId}`);
      return { date: '2026-10-10', workedMinutes: 60 };
    },
    getMyAttendance: async (caller, month) => {
      calls.push(`me:${caller.uid}:${month}`);
      return {
        month,
        today: '2026-10-10',
        serverTime: new Date('2026-10-10T10:00:00Z'),
        days: {},
      };
    },
  };
  const app = createApp({
    verifyIdToken: async () => identity(role === 'admin' ? 'admin-1' : 'emp-1', role),
    getProfile: async () => undefined,
    attendance,
  });
  return { app, calls };
}

const headers = {
  authorization: 'Bearer token',
  'content-type': 'application/json',
};
const validPunch = JSON.stringify({
  lat: 13,
  lng: 80,
  accuracy: 10,
  deviceId: 'device-1',
  isMocked: false,
});

test('attendance endpoints require a token and reject admin accounts', async () => {
  const { app } = makeApp();
  for (const [path, options] of [
    ['/attendance/check-in', { method: 'POST', headers: { 'content-type': 'application/json' }, body: validPunch }],
    ['/attendance/check-out', { method: 'POST', headers: { 'content-type': 'application/json' }, body: validPunch }],
    ['/attendance/me?month=2026-10', {}],
  ] as const) {
    assert.equal((await request(app, path, options)).status, 401);
  }

  const admin = makeApp('admin');
  for (const [path, options] of [
    ['/attendance/check-in', { method: 'POST', headers, body: validPunch }],
    ['/attendance/check-out', { method: 'POST', headers, body: validPunch }],
    ['/attendance/me?month=2026-10', { headers }],
  ] as const) {
    assert.equal((await request(admin.app, path, options)).status, 403);
  }
});

test('employee routes validate request parts and serialize timestamp responses', async () => {
  const { app, calls } = makeApp();
  const checkin = await request(app, '/attendance/check-in', {
    method: 'POST',
    headers,
    body: validPunch,
  });
  assert.equal(checkin.status, 201);
  assert.equal(checkin.body.inTime, '2026-10-10T10:00:00.000Z');

  const checkoutValid = await request(app, '/attendance/check-out', {
    method: 'POST',
    headers,
    body: validPunch,
  });
  assert.equal(checkoutValid.status, 200);

  const checkout = await request(app, '/attendance/check-out', {
    method: 'POST',
    headers,
    body: JSON.stringify({ ...JSON.parse(validPunch), clientTime: 'forbidden' }),
  });
  assert.equal(checkout.status, 400);
  assert.equal(checkout.body.error.code, 'VALIDATION_ERROR');

  const me = await request(app, '/attendance/me?month=2026-10', { headers });
  assert.equal(me.status, 200);
  assert.deepEqual(me.body, {
    month: '2026-10',
    today: '2026-10-10',
    serverTime: '2026-10-10T10:00:00.000Z',
    days: {},
  });
  assert.deepEqual(calls, [
    'in:emp-1:device-1',
    'out:emp-1:device-1',
    'me:emp-1:2026-10',
  ]);

  const badQuery = await request(app, '/attendance/me?month=2026-13', { headers });
  assert.equal(badQuery.status, 400);
});
