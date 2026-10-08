import assert from 'node:assert/strict';
import test from 'node:test';
import { Timestamp } from 'firebase-admin/firestore';
import { AppError } from '../errors/app-error';
import type {
  AttendanceBranch,
  AttendanceDay,
  AttendanceDocument,
  PayrollMonthDocument,
} from './attendance-store';
import type { EmployeeRecord } from './employee-service';
import type { HolidayRecord } from './holiday-service';
import { HolidayService } from './holiday-service';
import type { SettingsStore } from './settings-service';
import { SettingsService } from './settings-service';
import type {
  AttendanceEditAudit,
  AttendanceEditTransaction,
  AttendanceViewsStore,
  FlaggedCheckinRecord,
} from './attendance-views-store';
import { AttendanceViewsService } from './attendance-views-service';

const now = new Date('2026-10-10T10:00:00.000Z');
const admin = { uid: 'admin-1', role: 'admin' };
const employeeCaller = { uid: 'emp-1', role: 'employee' };
const employeesSeed: EmployeeRecord[] = [
  {
    uid: 'emp-1',
    empCode: 'EMP001',
    name: 'Asha',
    designation: 'Associate',
    role: 'employee',
    status: 'active',
    doj: '2026-10-01',
  },
  {
    uid: 'emp-2',
    empCode: 'EMP002',
    name: 'Bala',
    role: 'employee',
    status: 'inactive',
    doj: '2026-10-01',
  },
  {
    uid: 'emp-old',
    empCode: 'EMP003',
    name: 'Old',
    role: 'employee',
    status: 'inactive',
    doj: '2025-01-01',
    dol: '2026-09-30',
  },
];
const branch: AttendanceBranch = {
  id: 'branch-1',
  name: 'Chennai',
  lat: 13,
  lng: 80,
  radiusMeters: 100,
  status: 'active',
};

class FakeViewsStore implements AttendanceViewsStore, SettingsStore {
  settings: Record<string, unknown> | undefined;
  readonly attendance = new Map<string, AttendanceDocument>();
  readonly payrollMonths = new Map<string, PayrollMonthDocument>();
  readonly holidays = new Map<string, HolidayRecord>();
  readonly checkins: FlaggedCheckinRecord[] = [];
  readonly audits: AttendanceEditAudit[] = [];
  readonly events: string[] = [];

  serverTimestamp() {
    return Timestamp.fromDate(now);
  }

  async getCompanySettings() {
    return this.settings;
  }

  async mergeCompanySettings(values: Record<string, unknown>) {
    this.settings = { ...this.settings, ...values };
  }

  async getAttendance(id: string) {
    return this.attendance.get(id);
  }

  async getAttendanceDocuments(ids: string[]) {
    return new Map(
      ids.flatMap((id) => {
        const document = this.attendance.get(id);
        return document === undefined ? [] : [[id, document] as const];
      }),
    );
  }

  async getPayrollMonth(month: string) {
    return this.payrollMonths.get(month);
  }

  async listHolidays(fromDate: string, toDate: string) {
    return [...this.holidays.values()]
      .filter((holiday) => holiday.date >= fromDate && holiday.date <= toDate)
      .sort((left, right) => left.date.localeCompare(right.date));
  }

  async getHoliday(date: string) {
    return this.holidays.get(date);
  }

  async createHoliday(holiday: HolidayRecord) {
    if (this.holidays.has(holiday.date)) {
      throw new AppError(409, 'HOLIDAY_EXISTS', 'A holiday already exists.');
    }
    this.holidays.set(holiday.date, holiday);
  }

  async deleteHoliday(date: string) {
    return this.holidays.delete(date);
  }

  async listCheckinsByDate(fromDate: string, toDate: string) {
    return this.checkins.filter(
      (record) => String(record.date) >= fromDate && String(record.date) <= toDate,
    );
  }

  async runAttendanceEdit<T>(
    work: (transaction: AttendanceEditTransaction) => Promise<T>,
  ): Promise<T> {
    const stagedAttendance: Array<{
      id: string;
      empId: string;
      month: string;
      date: string;
      day: AttendanceDay;
    }> = [];
    const stagedAudits: AttendanceEditAudit[] = [];
    const transaction: AttendanceEditTransaction = {
      getAttendance: async (id) => {
        this.events.push('read-attendance');
        return this.attendance.get(id);
      },
      getPayrollMonth: async (month) => {
        this.events.push('read-payroll');
        return this.payrollMonths.get(month);
      },
      setAttendanceDay: (write) => {
        this.events.push('write-attendance');
        stagedAttendance.push(write);
      },
      createAudit: (audit) => {
        this.events.push('write-audit');
        stagedAudits.push(audit);
      },
    };
    const result = await work(transaction);
    for (const write of stagedAttendance) {
      const existing = this.attendance.get(write.id) ?? {
        empId: write.empId,
        month: write.month,
        days: {},
      };
      this.attendance.set(write.id, {
        ...existing,
        days: { ...existing.days, [write.date]: write.day },
      });
    }
    this.audits.push(...stagedAudits);
    return result;
  }
}

class FakeEmployees {
  readonly records = new Map(employeesSeed.map((employee) => [employee.uid!, employee]));

  async getEmployee(uid: string) {
    return this.records.get(uid);
  }

  async listEmployees() {
    return [...this.records.values()];
  }
}

function service() {
  const store = new FakeViewsStore();
  const employees = new FakeEmployees();
  const branches = { listBranches: async () => [branch] };
  return {
    store,
    employees,
    views: new AttendanceViewsService({ store, employees, branches, now: () => now }),
    holidays: new HolidayService(store),
    settings: new SettingsService(store),
  };
}

async function expectError(
  work: Promise<unknown>,
  status: number,
  code: string,
) {
  await assert.rejects(work, (error: unknown) => {
    assert.ok(error instanceof AppError);
    assert.equal(error.status, status);
    assert.equal(error.code, code);
    return true;
  });
}

test('settings returns all defaults and PATCH records editor with effective values', async () => {
  const { store, settings } = service();
  assert.deepEqual(await settings.getSettings(admin), {
    companyName: '',
    weeklyOffDays: [0],
    perDayBasis: 'calendar',
    maxAccuracyMeters: 100,
    rejectMockLocation: true,
    enforceCheckoutLocation: false,
  });
  const result = await settings.updateSettings(
    admin,
    { companyName: 'Example', weeklyOffDays: [0, 6], perDayBasis: 'working' },
  );
  assert.equal(result.companyName, 'Example');
  assert.deepEqual(result.weeklyOffDays, [0, 6]);
  assert.equal(result.perDayBasis, 'working');
  assert.equal(result.editedBy, admin.uid);
  assert.ok(store.settings?.updatedAt instanceof Timestamp);
  await expectError(
    settings.getSettings(employeeCaller),
    403,
    'FORBIDDEN',
  );
});

test('holidays create, list sorted, reject duplicates and locked months, and delete', async () => {
  const { store, holidays } = service();
  await holidays.createHoliday(admin, { date: '2026-10-20', name: 'Second' });
  await holidays.createHoliday(admin, { date: '2026-10-02', name: 'First' });
  assert.deepEqual(
    (await holidays.listHolidays(employeeCaller, '2026')).map(({ date }) => date),
    ['2026-10-02', '2026-10-20'],
  );
  await expectError(
    holidays.createHoliday(admin, { date: '2026-10-20', name: 'Duplicate' }),
    409,
    'HOLIDAY_EXISTS',
  );
  store.payrollMonths.set('2026-10', { locked: true });
  await expectError(
    holidays.deleteHoliday(admin, '2026-10-20'),
    409,
    'MONTH_LOCKED',
  );
  store.payrollMonths.delete('2026-10');
  await holidays.deleteHoliday(admin, '2026-10-20');
  await expectError(holidays.deleteHoliday(admin, '2026-10-20'), 404, 'HOLIDAY_NOT_FOUND');
  await expectError(
    holidays.createHoliday(employeeCaller, { date: '2026-10-21', name: 'No' }),
    403,
    'FORBIDDEN',
  );
});

test('by-date includes eligible employees without a doc, excludes leavers, and marks open punches', async () => {
  const { store, views } = service();
  store.attendance.set('2026-10_emp-1', {
    empId: 'emp-1',
    month: '2026-10',
    days: {
      '2026-10-09': {
        status: 'P',
        inTime: Timestamp.fromDate(new Date('2026-10-09T03:30:00.000Z')),
        inBranchId: 'branch-1',
      },
      '2026-10-10': {
        status: 'P',
        inTime: Timestamp.fromDate(new Date('2026-10-10T03:30:00.000Z')),
        inBranchId: 'missing-branch',
      },
    },
  });
  const past = await views.getByDate(admin, '2026-10-09');
  const pastRows = past.rows as Array<Record<string, unknown>>;
  assert.deepEqual(pastRows.map((row) => row.empId), ['emp-1', 'emp-2']);
  assert.equal(pastRows[0]?.noCheckout, true);
  assert.equal(pastRows[0]?.checkedInNow, false);
  assert.equal(pastRows[0]?.inBranchName, 'Chennai');
  assert.equal(pastRows[1]?.status, 'A');

  const today = await views.getByDate(admin, '2026-10-10');
  const todayRows = today.rows as Array<Record<string, unknown>>;
  assert.equal(todayRows[0]?.checkedInNow, true);
  assert.equal(todayRows[0]?.noCheckout, false);
  assert.equal(todayRows[0]?.inBranchName, 'missing-branch');

  const future = await views.getByDate(admin, '2026-10-12');
  assert.equal((future.rows as Array<Record<string, unknown>>)[0]?.status, 'PENDING');
  assert.equal(future.totals.PENDING, 2);
});

test('calendar and summaries enforce employee ownership and include branch names', async () => {
  const { store, views } = service();
  store.attendance.set('2026-10_emp-1', {
    empId: 'emp-1',
    month: '2026-10',
    days: {
      '2026-10-09': {
        status: 'P',
        inBranchId: 'branch-1',
        outBranchId: 'unknown',
      },
    },
  });
  const calendar = await views.getMyCalendar(employeeCaller, '2026-10');
  const days = calendar.days as Array<Record<string, unknown>>;
  const saved = days.find((day) => day.date === '2026-10-09');
  assert.equal(saved?.inBranchName, 'Chennai');
  assert.equal(saved?.outBranchName, 'unknown');
  await expectError(
    views.getMyCalendar(admin, '2026-10'),
    403,
    'FORBIDDEN',
  );
  await expectError(
    views.getSummary(employeeCaller, '2026-10', 'emp-2'),
    403,
    'FORBIDDEN',
  );
  const own = await views.getSummary(employeeCaller, '2026-10');
  assert.equal((own as Record<string, unknown>).empId, 'emp-1');
  const all = await views.getSummary(admin, '2026-10');
  assert.equal((all as Array<unknown>).length, 2);
});

test('admin edits all statuses transactionally and clears punches for non-punch statuses', async () => {
  const { store, views } = service();
  const base = {
    caller: admin,
    empId: 'emp-1',
    date: '2026-10-09',
    reason: 'Approved correction',
  };
  for (const status of ['P', 'H', 'A', 'L', 'UL'] as const) {
    const result = await views.editAttendance({
      ...base,
      status,
      ...(status === 'P' || status === 'H'
        ? {
            inTime: '2026-10-09T03:30:00.000Z',
            outTime: '2026-10-09T05:45:59.000Z',
          }
        : {}),
    });
    assert.equal(result.status, status);
    const saved = store.attendance.get('2026-10_emp-1')?.days['2026-10-09'];
    assert.equal(saved?.source, 'admin_edit');
    assert.equal(saved?.editedBy, admin.uid);
    assert.ok(saved?.editedAt instanceof Timestamp);
    if (status === 'P' || status === 'H') assert.equal(saved?.workedMinutes, 135);
    else {
      assert.equal('inTime' in (saved ?? {}), false);
      assert.equal('outTime' in (saved ?? {}), false);
      assert.equal('inBranchId' in (saved ?? {}), false);
      assert.equal('inDistance' in (saved ?? {}), false);
    }
  }
  assert.equal(store.audits.length, 5);
  assert.deepEqual(store.events.slice(0, 4), [
    'read-attendance',
    'read-payroll',
    'write-attendance',
    'write-audit',
  ]);
  assert.equal(store.audits[0]?.action, 'attendance.edit');
  assert.equal(store.audits[0]?.by, admin.uid);
  assert.equal(store.audits[0]?.reason, base.reason);
});

test('admin edits reject future, out-of-window, locked, and invalid times', async () => {
  const { store, employees, views } = service();
  const base = {
    caller: admin,
    empId: 'emp-1',
    date: '2026-10-09',
    status: 'P' as const,
    reason: 'Correction',
  };
  await expectError(
    views.editAttendance({ ...base, date: '2026-10-11' }),
    422,
    'FUTURE_ATTENDANCE_DATE',
  );
  employees.records.set('emp-1', { ...employeesSeed[0]!, doj: '2026-10-10' });
  await expectError(views.editAttendance(base), 422, 'OUTSIDE_EMPLOYMENT_WINDOW');
  employees.records.set('emp-1', { ...employeesSeed[0]!, doj: '2026-10-01', dol: '2026-10-08' });
  await expectError(views.editAttendance(base), 422, 'OUTSIDE_EMPLOYMENT_WINDOW');
  employees.records.set('emp-1', employeesSeed[0]!);
  store.payrollMonths.set('2026-10', { locked: true });
  await expectError(views.editAttendance(base), 409, 'MONTH_LOCKED');
  store.payrollMonths.clear();
  await expectError(
    views.editAttendance({
      ...base,
      inTime: '2026-10-09T05:00:00.000Z',
      outTime: '2026-10-09T04:00:00.000Z',
    }),
    422,
    'INVALID_ATTENDANCE_TIMES',
  );
  await expectError(
    views.editAttendance({
      ...base,
      outTime: '2026-10-09T04:00:00.000Z',
    }),
    422,
    'OUT_TIME_WITHOUT_IN_TIME',
  );
});

test('flagged check-ins include rejected metadata only and omit coordinates', async () => {
  const { store, views } = service();
  store.checkins.push(
    {
      id: 'accepted',
      empId: 'emp-1',
      type: 'in',
      date: '2026-10-09',
      serverTime: new Date('2026-10-09T09:00:00.000Z'),
      accepted: true,
      lat: 13,
      lng: 80,
    },
    {
      id: 'rejected',
      empId: 'emp-1',
      type: 'in',
      date: '2026-10-09',
      serverTime: new Date('2026-10-09T10:00:00.000Z'),
      accepted: false,
      rejectReason: 'OUTSIDE_GEOFENCE',
      branchId: 'branch-1',
      distance: 1000,
      accuracy: 10,
      isMocked: false,
      deviceId: 'install-1',
      lat: 13,
      lng: 80,
    },
  );
  const result = await views.getFlaggedCheckins(admin, {
    from: '2026-10-09',
    to: '2026-10-09',
  });
  assert.equal(result.length, 1);
  assert.equal(result[0]?.id, 'rejected');
  assert.equal(result[0]?.nearestBranchName, 'Chennai');
  assert.equal('lat' in (result[0] ?? {}), false);
  assert.equal('lng' in (result[0] ?? {}), false);
  await expectError(
    views.getFlaggedCheckins(admin, { from: '2026-09-01', to: '2026-10-10' }),
    400,
    'INVALID_DATE_RANGE',
  );
});
