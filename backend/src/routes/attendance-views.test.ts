import assert from 'node:assert/strict';
import { createServer } from 'node:http';
import test from 'node:test';
import type { DecodedIdToken } from 'firebase-admin/auth';
import { createApp } from '../app';
import type { AttendanceOperations } from './attendance';
import type { AttendanceViewsOperations } from './attendance-views';
import type { HolidayOperations } from './holidays';
import type { SettingsOperations } from './settings';

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
    const body = await response.text();
    return {
      status: response.status,
      body: body.length === 0 ? undefined : JSON.parse(body),
    };
  } finally {
    await new Promise<void>((resolve, reject) => {
      server.close((error) => (error ? reject(error) : resolve()));
    });
  }
}

const headers = {
  authorization: 'Bearer test-token',
  'content-type': 'application/json',
};

function makeApp() {
  const calls: string[] = [];
  const attendance: AttendanceOperations = {
    checkIn: async () => ({}),
    checkOut: async () => ({}),
    getMyAttendance: async (_caller, month) => {
      calls.push(`step4-me:${month}`);
      return {
        month,
        today: '2026-10-08',
        serverTime: new Date('2026-10-08T10:00:00Z'),
        days: {},
      };
    },
  };
  const views: AttendanceViewsOperations = {
    getMyCalendar: async (caller, month) => {
      calls.push(`my-calendar:${caller.uid}:${month}`);
      return { month, summary: {}, days: [] };
    },
    getEmployeeCalendar: async (_caller, id, month) => ({
      id,
      month,
      summary: {},
      days: [],
    }),
    getSummary: async (_caller, month, empId) => ({ month, empId }),
    getByDate: async (_caller, date) => ({ date, rows: [], totals: {} }),
    editAttendance: async (input) => ({ ...input, caller: undefined }),
    getFlaggedCheckins: async () => [],
  };
  const settings: SettingsOperations = {
    getSettings: async () => ({ companyName: '' }),
    updateSettings: async (_caller, changes) => changes,
  };
  const holidays: HolidayOperations = {
    listHolidays: async () => [],
    createHoliday: async (_caller, holiday) => holiday,
    deleteHoliday: async () => {},
  };
  const app = createApp({
    verifyIdToken: async (token) =>
      identity(
        token === 'employee-token' ? 'emp-1' : 'admin-1',
        token === 'employee-token' ? 'employee' : 'admin',
      ),
    getProfile: async () => undefined,
    attendance,
    attendanceViews: views,
    settings,
    holidays,
  });
  return { app, calls };
}

test('Step 5 endpoints require ID tokens and enforce admin/employee roles', async () => {
  const { app } = makeApp();
  const adminOnly: Array<[string, RequestInit?]> = [
    ['/settings'],
    ['/settings', { method: 'PATCH', headers, body: JSON.stringify({ companyName: 'X' }) }],
    ['/holidays', { method: 'POST', headers, body: JSON.stringify({ date: '2026-10-10', name: 'X' }) }],
    ['/holidays/2026-10-10', { method: 'DELETE', headers }],
    ['/attendance?date=2026-10-10'],
    ['/attendance/employee/emp-1/calendar?month=2026-10'],
    ['/attendance/emp-1/2026-10-10', { method: 'PATCH', headers, body: JSON.stringify({ status: 'P', reason: 'Fix' }) }],
    ['/checkins/flagged'],
  ];
  for (const [path, options] of adminOnly) {
    const noAuthHeaders = new Headers(options?.headers);
    noAuthHeaders.delete('authorization');
    assert.equal(
      (
        await request(app, path, {
          ...options,
          headers: noAuthHeaders,
        })
      ).status,
      401,
      path,
    );
    const adminResult = await request(app, path, { ...options, headers });
    assert.equal(
      adminResult.status,
      options?.method === 'DELETE'
        ? 204
        : options?.method === 'POST'
          ? 201
          : 200,
      `${path} admin token`,
    );
    assert.equal(
      (
        await request(app, path, {
          ...options,
          headers: { ...headers, authorization: 'Bearer employee-token' },
        })
      ).status,
      403,
      `${path} employee token`,
    );
  }
  assert.equal(
    (
      await request(app, '/attendance/me/calendar?month=2026-10', {
        headers,
      })
    ).status,
    403,
  );
  assert.equal(
    (
      await request(app, '/attendance/me/calendar?month=2026-10', {
        headers: { ...headers, authorization: 'Bearer employee-token' },
      })
    ).status,
    200,
  );
  assert.equal(
    (
      await request(app, '/holidays?year=2026', {
        headers: { ...headers, authorization: 'Bearer employee-token' },
      })
    ).status,
    200,
  );
});

test('view routes validate requests and preserve the Step 4 GET /attendance/me response', async () => {
  const { app, calls } = makeApp();
  const invalid: Array<[string, RequestInit?]> = [
    ['/settings?unknown=x'],
    [
      '/settings',
      { method: 'PATCH', headers, body: JSON.stringify({ unknown: true }) },
    ],
    [
      '/settings',
      { method: 'PATCH', headers, body: JSON.stringify({ weeklyOffDays: [0, 0] }) },
    ],
    [
      '/settings',
      { method: 'PATCH', headers, body: JSON.stringify({ maxAccuracyMeters: 9 }) },
    ],
    ['/holidays?year=20x6'],
    [
      '/holidays',
      { method: 'POST', headers, body: JSON.stringify({ date: '2026-10-10', name: 'X', extra: 1 }) },
    ],
    ['/attendance/me/calendar?month=2026-13'],
    ['/attendance/summary?month=2026-10&unknown=x'],
    ['/attendance?date=2026-02-30'],
    [
      '/attendance/emp-1/2026-10-10',
      { method: 'PATCH', headers, body: JSON.stringify({ status: 'A', inTime: '2026-10-10T10:00:00Z', reason: 'Fix' }) },
    ],
    [
      '/attendance/emp-1/2026-10-10',
      { method: 'PATCH', headers, body: JSON.stringify({ status: 'P' }) },
    ],
    ['/checkins/flagged?from=2026-10-10&to=2026-10-01'],
  ];
  for (const [path, options] of invalid) {
    const requestHeaders =
      path.startsWith('/attendance/me/calendar')
        ? { ...headers, authorization: 'Bearer employee-token' }
        : headers;
    const result = await request(app, path, {
      ...options,
      headers: requestHeaders,
    });
    assert.equal(result.status, 400, path);
  }

  const legacy = await request(app, '/attendance/me?month=2026-10', {
    headers: { ...headers, authorization: 'Bearer employee-token' },
  });
  assert.equal(legacy.status, 200);
  assert.deepEqual(legacy.body, {
    month: '2026-10',
    today: '2026-10-08',
    serverTime: '2026-10-08T10:00:00.000Z',
    days: {},
  });
  assert.deepEqual(calls, ['step4-me:2026-10']);
});
