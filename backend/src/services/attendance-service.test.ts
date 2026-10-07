import assert from 'node:assert/strict';
import test from 'node:test';
import { Timestamp } from 'firebase-admin/firestore';
import { AppError } from '../errors/app-error';
import type { EmployeeRecord } from './employee-service';
import type {
  AttendanceBranch,
  AttendanceDay,
  AttendanceEmployeeStore,
  AttendanceStore,
  AttendanceTransaction,
  CheckinRecord,
} from './attendance-store';
import { AttendanceService } from './attendance-service';

const employee: EmployeeRecord = {
  uid: 'emp-1',
  role: 'employee',
  status: 'active',
  doj: '2026-10-01',
  primaryBranchId: 'branch-1',
  allowedBranchIds: ['branch-1'],
};

const branch: AttendanceBranch = {
  id: 'branch-1',
  name: 'Chennai',
  lat: 13,
  lng: 80,
  radiusMeters: 100,
  status: 'active',
};

const caller = { uid: 'emp-1', role: 'employee' };
const input = {
  lat: 13,
  lng: 80,
  accuracy: 5,
  deviceId: 'device-1',
  isMocked: false,
};
const currentTime = new Date('2026-10-10T10:00:00.000Z');

class FakeAttendanceStore implements AttendanceStore {
  readonly attendance = new Map<string, AttendanceDocument>();
  readonly payrollMonths = new Map<string, { locked?: boolean }>();
  readonly checkins: CheckinRecord[] = [];
  settings: Record<string, unknown> | undefined;
  failRejectedWrites = false;
  clock = currentTime;
  private transactionTail: Promise<void> = Promise.resolve();

  serverTimestamp() {
    return Timestamp.fromDate(this.clock);
  }

  async getAttendance(id: string) {
    return this.attendance.get(id);
  }

  async getCompanySettings() {
    return this.settings;
  }

  async recordCheckin(record: CheckinRecord) {
    if (this.failRejectedWrites) throw new Error('fake logging failure');
    this.checkins.push(record);
  }

  async runTransaction<T>(
    work: (transaction: AttendanceTransaction) => Promise<T>,
  ): Promise<T> {
    const previous = this.transactionTail;
    let release!: () => void;
    this.transactionTail = new Promise<void>((resolve) => (release = resolve));
    await previous;
    const stagedDays: Array<{
      id: string;
      empId: string;
      month: string;
      date: string;
      day: AttendanceDay;
    }> = [];
    const stagedCheckins: CheckinRecord[] = [];
    const transaction: AttendanceTransaction = {
      getAttendance: async (id) => this.attendance.get(id),
      getPayrollMonth: async (month) => this.payrollMonths.get(month),
      setAttendanceDay: (write) => stagedDays.push(write),
      createCheckin: (record) => stagedCheckins.push(record),
    };
    try {
      const result = await work(transaction);
      for (const write of stagedDays) {
        const document = this.attendance.get(write.id) ?? {
          empId: write.empId,
          month: write.month,
          days: {},
        };
        this.attendance.set(write.id, {
          ...document,
          days: { ...document.days, [write.date]: write.day },
        });
      }
      this.checkins.push(...stagedCheckins);
      return result;
    } finally {
      release();
    }
  }
}

class FakeEmployeeStore implements AttendanceEmployeeStore {
  current: EmployeeRecord | undefined = { ...employee };
  async getEmployee() {
    return this.current;
  }
}

function service(options: {
  store?: FakeAttendanceStore;
  employees?: FakeEmployeeStore;
  branches?: AttendanceBranch[];
  now?: () => Date;
  settings?: Record<string, unknown>;
  logFailure?: () => void;
} = {}) {
  const store = options.store ?? new FakeAttendanceStore();
  const employees = options.employees ?? new FakeEmployeeStore();
  const now = options.now ?? (() => currentTime);
  store.clock = now();
  store.settings = options.settings;
  return {
    store,
    employees,
    service: new AttendanceService({
      store,
      employees,
      branches: { listBranches: async () => options.branches ?? [branch] },
      now,
      logRejectedWriteFailure: options.logFailure,
    }),
  };
}

async function expectError(
  work: Promise<unknown>,
  status: number,
  code: string,
  message?: string,
) {
  await assert.rejects(work, (error: unknown) => {
    assert.ok(error instanceof AppError);
    assert.equal(error.status, status);
    assert.equal(error.code, code);
    if (message !== undefined) assert.equal(error.message, message);
    return true;
  });
}

test('check-in persists the accepted punch and responds with the stored time', async () => {
  const { store, service: attendance } = service();
  const result = await attendance.checkIn(caller, input);
  assert.deepEqual(result, {
    date: '2026-10-10',
    status: 'P',
    inTime: Timestamp.fromDate(currentTime),
    branchId: 'branch-1',
    branchName: 'Chennai',
    distanceMeters: 0,
  });
  assert.equal(store.checkins[0]?.accepted, true);
  assert.equal(store.attendance.get('2026-10_emp-1')?.days['2026-10-10']?.source, 'app');
});

test('duplicate and racing check-ins cannot overwrite an existing punch', async () => {
  const { store, service: attendance } = service();
  await attendance.checkIn(caller, input);
  await expectError(attendance.checkIn(caller, input), 409, 'ALREADY_CHECKED_IN');

  const racing = service();
  const results = await Promise.allSettled([
    racing.service.checkIn(caller, input),
    racing.service.checkIn(caller, input),
  ]);
  assert.equal(results.filter((result) => result.status === 'fulfilled').length, 1);
  assert.equal(racing.store.checkins.length, 1);
});

test('check-in rejects and records outside, inaccurate, mocked, and unassigned attempts', async () => {
  const outside = service();
  await expectError(
    outside.service.checkIn(caller, { ...input, lat: 13.02 }),
    422,
    'OUTSIDE_GEOFENCE',
  );
  assert.equal(outside.store.checkins[0]?.rejectReason, 'OUTSIDE_GEOFENCE');

  const inaccurate = service({ settings: { maxAccuracyMeters: 10 } });
  await expectError(
    inaccurate.service.checkIn(caller, { ...input, accuracy: 11 }),
    422,
    'ACCURACY_TOO_LOW',
  );
  const mocked = service();
  await expectError(
    mocked.service.checkIn(caller, { ...input, isMocked: true }),
    422,
    'MOCK_LOCATION',
  );
  const unassigned = service({
    employees: Object.assign(new FakeEmployeeStore(), {
      current: { ...employee, allowedBranchIds: [] },
    }),
    branches: [],
  });
  await expectError(
    unassigned.service.checkIn(caller, input),
    422,
    'NO_BRANCH_ASSIGNED',
    'This employee has no active branch assigned.',
  );
});

test('failed rejected-attempt logging preserves the original business error', async () => {
  let logged = 0;
  const { service: attendance } = service({
    store: Object.assign(new FakeAttendanceStore(), { failRejectedWrites: true }),
    logFailure: () => logged++,
  });
  await expectError(
    attendance.checkIn(caller, { ...input, lat: 13.02 }),
    422,
    'OUTSIDE_GEOFENCE',
  );
  assert.equal(logged, 1);
});

test('employee eligibility, admin access, and payroll locking are enforced', async () => {
  const admin = service();
  await expectError(
    admin.service.checkIn({ uid: 'admin-1', role: 'admin' }, input),
    403,
    'FORBIDDEN',
  );
  const inactive = service();
  inactive.employees.current = { ...employee, status: 'inactive' };
  await expectError(inactive.service.checkIn(caller, input), 403, 'FORBIDDEN');
  const adminProfile = service();
  adminProfile.employees.current = { ...employee, role: 'admin' };
  await expectError(adminProfile.service.checkIn(caller, input), 403, 'FORBIDDEN');
  const notJoined = service();
  notJoined.employees.current = { ...employee, doj: '2026-10-11' };
  await expectError(notJoined.service.checkIn(caller, input), 422, 'NOT_YET_JOINED');
  const locked = service();
  locked.store.payrollMonths.set('2026-10', { locked: true });
  await expectError(locked.service.checkIn(caller, input), 409, 'MONTH_LOCKED');
});

test('checkout writes worked time to the check-in day and rejects repeat checkout', async () => {
  const { store, service: attendance } = service();
  const inTime = new Date('2026-10-10T09:00:30.000Z');
  store.attendance.set('2026-10_emp-1', {
    empId: 'emp-1',
    month: '2026-10',
    days: {
      '2026-10-10': { status: 'P', inTime: Timestamp.fromDate(inTime) },
    },
  });
  const result = await attendance.checkOut(caller, input);
  assert.equal(result.date, '2026-10-10');
  assert.equal(result.workedMinutes, 59);
  assert.equal(
    store.attendance.get('2026-10_emp-1')?.days['2026-10-10']?.workedMinutes,
    59,
  );
  await expectError(attendance.checkOut(caller, input), 409, 'ALREADY_CHECKED_OUT');
});

test('checkout finds yesterday across a month boundary and rejects missing punches', async () => {
  const { store, service: attendance } = service({
    now: () => new Date('2026-11-01T01:00:00.000Z'),
  });
  store.attendance.set('2026-10_emp-1', {
    empId: 'emp-1',
    month: '2026-10',
    days: {
      '2026-10-31': {
        status: 'P',
        inTime: Timestamp.fromDate(new Date('2026-10-31T17:00:00.000Z')),
      },
    },
  });
  const result = await attendance.checkOut(caller, input);
  assert.equal(result.date, '2026-10-31');
  assert.equal(result.workedMinutes, 480);

  const empty = service();
  await expectError(empty.service.checkOut(caller, input), 409, 'NOT_CHECKED_IN');
});

test('checkout after IST midnight remains on the late-night check-in day', async () => {
  const { store, service: attendance } = service({
    now: () => new Date('2026-10-10T18:30:00.000Z'),
  });
  store.attendance.set('2026-10_emp-1', {
    empId: 'emp-1',
    month: '2026-10',
    days: {
      '2026-10-10': {
        status: 'P',
        inTime: Timestamp.fromDate(new Date('2026-10-10T18:25:00.000Z')),
      },
    },
  });
  const result = await attendance.checkOut(caller, input);
  assert.equal(result.date, '2026-10-10');
  assert.equal(result.workedMinutes, 5);
});

test('checkout location enforcement defaults off and can be enabled', async () => {
  const setupOpenPunch = (store: FakeAttendanceStore) => {
    store.attendance.set('2026-10_emp-1', {
      empId: 'emp-1',
      month: '2026-10',
      days: {
        '2026-10-10': {
          inTime: Timestamp.fromDate(new Date('2026-10-10T09:00:00.000Z')),
        },
      },
    });
  };
  const unenforced = service({ settings: { enforceCheckoutLocation: false } });
  setupOpenPunch(unenforced.store);
  await unenforced.service.checkOut(caller, { ...input, lat: 13.02, accuracy: 500 });

  const enforced = service({ settings: { enforceCheckoutLocation: true } });
  setupOpenPunch(enforced.store);
  await expectError(
    enforced.service.checkOut(caller, { ...input, lat: 13.02 }),
    422,
    'OUTSIDE_GEOFENCE',
  );

  const inaccurate = service({
    settings: { enforceCheckoutLocation: true, maxAccuracyMeters: 10 },
  });
  setupOpenPunch(inaccurate.store);
  await expectError(
    inaccurate.service.checkOut(caller, { ...input, accuracy: 11 }),
    422,
    'ACCURACY_TOO_LOW',
  );
});

test('GET my attendance returns empty days and server-derived date and time', async () => {
  const { service: attendance } = service();
  assert.deepEqual(await attendance.getMyAttendance(caller, '2026-10'), {
    month: '2026-10',
    today: '2026-10-10',
    serverTime: currentTime,
    days: {},
  });
  await expectError(
    attendance.getMyAttendance({ uid: 'admin-1', role: 'admin' }, '2026-10'),
    403,
    'FORBIDDEN',
  );
});
