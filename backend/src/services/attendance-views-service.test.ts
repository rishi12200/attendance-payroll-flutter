import assert from 'node:assert/strict';
import test from 'node:test';
import { Timestamp } from 'firebase-admin/firestore';
import { AppError } from '../errors/app-error';
import { normalizeHoliday } from '../domain/holidays';
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
import type { LeaveTypeRecord } from './leave-type-service';
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
    primaryBranchId: 'branch-1',
  },
  {
    uid: 'emp-2',
    empCode: 'EMP002',
    name: 'Bala',
    role: 'employee',
    status: 'inactive',
    doj: '2026-10-01',
    primaryBranchId: 'branch-2',
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
  employeeBranch: string | null = 'branch-1';
  readonly attendance = new Map<string, AttendanceDocument>();
  readonly payrollMonths = new Map<string, PayrollMonthDocument>();
  readonly holidays = new Map<string, HolidayRecord>();
  readonly checkins: FlaggedCheckinRecord[] = [];
  readonly leaveTypes: LeaveTypeRecord[] = [{
    id: 'annual', name: 'Annual Leave', code: 'AL', paid: true,
    annualQuotaDays: 18, allowHalfDay: true, status: 'active', system: false, sortOrder: 1,
  }];
  leaveTypeReads = 0;
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
      .map((holiday) => normalizeHoliday(holiday.id, holiday))
      .filter((holiday) => holiday !== undefined && holiday.date! >= fromDate && holiday.date! <= toDate)
      .sort((left, right) => left!.date!.localeCompare(right!.date!)) as HolidayRecord[];
  }

  async listLeaveTypes() { this.leaveTypeReads += 1; return this.leaveTypes; }

  async listAllHolidays() { return [...this.holidays.values()]; }
  async listHolidayBranches() { return [{ id: 'branch-1', state: 'Tamil Nadu', status: 'active' }, { id: 'branch-2', state: 'Kerala', status: 'active' }]; }
  async getEmployeeBranch() { return this.employeeBranch; }

  async getHoliday(id: string) {
    return this.holidays.get(id);
  }

  async writeHoliday(input: { values: Record<string, unknown>; audit: Record<string, unknown> }) {
    const id = `holiday-${this.holidays.size + 1}`;
    this.holidays.set(id, { ...input.values, id } as HolidayRecord);
    return id;
  }

  async deleteHoliday(id: string) {
    return this.holidays.delete(id);
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
    leaveYearStartMonth: 1,
  });
  const result = await settings.updateSettings(
    admin,
    { companyName: 'Example', weeklyOffDays: [0, 6], perDayBasis: 'working', leaveYearStartMonth: 4 },
  );
  assert.equal(result.companyName, 'Example');
  assert.deepEqual(result.weeklyOffDays, [0, 6]);
  assert.equal(result.perDayBasis, 'working');
  assert.equal(result.leaveYearStartMonth, 4);
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
  await holidays.createHoliday(admin, { date: '2026-10-20', name: 'Second', scope: 'all' });
  await holidays.createHoliday(admin, { date: '2026-10-02', name: 'First', scope: 'all' });
  assert.deepEqual(
    (await holidays.listHolidays(employeeCaller, '2026')).map(({ date }) => date),
    ['2026-10-02', '2026-10-20'],
  );
  await assert.rejects(
    holidays.createHoliday(admin, { date: '2026-10-20', name: 'A different name', scope: 'all' }),
    (error: unknown) => {
      assert.ok(error instanceof AppError);
      assert.equal(error.status, 409);
      assert.equal(error.code, 'HOLIDAY_EXISTS');
      assert.equal(error.message, 'A holiday already exists on this date for some of these branches.');
      assert.deepEqual(error.details, {
        conflictingHolidayIds: ['holiday-1'],
        conflictingNames: ['Second'],
        holidayId: 'holiday-1',
      });
      return true;
    },
  );
  store.payrollMonths.set('2026-10', { locked: true });
  await expectError(
    holidays.deleteHoliday(admin, 'holiday-1'),
    409,
    'MONTH_LOCKED',
  );
  store.payrollMonths.delete('2026-10');
  await holidays.deleteHoliday(admin, 'holiday-1');
  await expectError(holidays.deleteHoliday(admin, 'holiday-1'), 404, 'HOLIDAY_NOT_FOUND');
  await expectError(
    holidays.createHoliday(employeeCaller, { date: '2026-10-21', name: 'No', scope: 'all' }),
    403,
    'FORBIDDEN',
  );
});

test('branch-scoped holidays do not conflict with disjoint scopes and are filtered per employee', async () => {
  const { store, holidays } = service();
  const branchA = await holidays.createHoliday(admin, { date: '2026-10-21', name: 'Regional', scope: 'branches', branchIds: ['branch-1'] });
  const branchB = await holidays.createHoliday(admin, { date: '2026-10-21', name: 'Regional', scope: 'branches', branchIds: ['branch-2'] });
  assert.notEqual(branchA.id, branchB.id);
  assert.deepEqual((await holidays.listHolidays(admin, '2026', 'branch-2')).map(({ id }) => id), [branchB.id]);
  await assert.rejects(
    holidays.createHoliday(admin, { date: '2026-10-21', name: 'Different name', scope: 'branches', branchIds: ['branch-1'] }),
    (error: unknown) => error instanceof AppError && error.code === 'HOLIDAY_EXISTS',
  );
  assert.deepEqual((await holidays.listMine(employeeCaller, '2026')).map(({ id }) => id), [branchA.id]);
  store.employeeBranch = null;
  assert.deepEqual(await holidays.listMine(employeeCaller, '2026'), []);
});

test('employee without a primary branch receives only all-scope holidays', async () => {
  const { store, holidays } = service();
  const all = await holidays.createHoliday(admin, { date: '2026-10-20', name: 'National', scope: 'all' });
  await holidays.createHoliday(admin, { date: '2026-10-21', name: 'Regional', scope: 'branches', branchIds: ['branch-1'] });
  store.employeeBranch = null;
  assert.deepEqual((await holidays.listMine(employeeCaller, '2026')).map(({ id }) => id), [all.id]);
});

test('legacy date-keyed holiday blocks any new holiday on that date', async () => {
  const { store, holidays } = service();
  store.holidays.set('2026-10-22', { id: '2026-10-22', name: 'Old holiday' } as unknown as HolidayRecord);
  await assert.rejects(
    holidays.createHoliday(admin, { date: '2026-10-22', name: 'New name', scope: 'branches', branchIds: ['branch-1'] }),
    (error: unknown) => {
      assert.ok(error instanceof AppError);
      assert.equal(error.code, 'HOLIDAY_EXISTS');
      assert.deepEqual(error.details, {
        conflictingHolidayIds: ['2026-10-22'],
        conflictingNames: ['Old holiday'],
        holidayId: '2026-10-22',
      });
      return true;
    },
  );
});

test('new holiday succeeds on another date and after the conflict is deleted', async () => {
  const { store, holidays } = service();
  const original = await holidays.createHoliday(admin, { date: '2026-10-24', name: 'Original', scope: 'all' });
  const otherDate = await holidays.createHoliday(admin, { date: '2026-10-25', name: 'Same scope', scope: 'all' });
  assert.equal(otherDate.date, '2026-10-25');
  await holidays.deleteHoliday(admin, original.id);
  const replacement = await holidays.createHoliday(admin, { date: '2026-10-24', name: 'Replacement', scope: 'all' });
  assert.equal(replacement.date, '2026-10-24');
  assert.equal(store.holidays.has(original.id), false);
});

test('listing keeps pre-existing overlapping holiday documents visible', async () => {
  const { store, holidays } = service();
  store.holidays.set('legacy-a', { id: 'legacy-a', date: '2026-10-26', name: 'Legacy A' } as unknown as HolidayRecord);
  store.holidays.set('legacy-b', { id: 'legacy-b', date: '2026-10-26', name: 'Legacy B' } as unknown as HolidayRecord);
  const listed = await holidays.listHolidays(admin, '2026');
  assert.deepEqual(listed.filter((item) => item.date === '2026-10-26').map(({ id }) => id), ['legacy-a', 'legacy-b']);
});

test('holiday conflict details include at most ten overlaps and keep the first ID', async () => {
  const { store, holidays } = service();
  for (let index = 0; index < 12; index++) {
    const id = `legacy-${index}`;
    store.holidays.set(id, {
      id,
      date: '2026-10-27',
      name: `Old ${index}`,
      scope: 'all',
      branchIds: [],
    });
  }
  await assert.rejects(
    holidays.createHoliday(admin, { date: '2026-10-27', name: 'New', scope: 'all' }),
    (error: unknown) => {
      assert.ok(error instanceof AppError);
      assert.equal((error.details?.conflictingHolidayIds as string[]).length, 10);
      assert.equal((error.details?.conflictingNames as string[]).length, 10);
      assert.equal(error.details?.holidayId, 'legacy-0');
      return true;
    },
  );
});

function seedBranchHoliday(store: FakeViewsStore, id: string, branchId: string) {
  store.holidays.set(id, {
    id,
    date: '2026-10-09',
    name: `Holiday ${branchId}`,
    scope: 'branches',
    branchIds: [branchId],
  });
}

test('employee calendars show only holidays for the employee primary branch', async () => {
  const { store, views } = service();
  seedBranchHoliday(store, 'holiday-a', 'branch-1');
  seedBranchHoliday(store, 'holiday-b', 'branch-2');

  const own = await views.getMyCalendar(employeeCaller, '2026-10');
  const ownDays = own.days as Array<Record<string, unknown>>;
  assert.equal(ownDays.find((day) => day.date === '2026-10-09')?.holidayName, 'Holiday branch-1');
  assert.equal((own.summary as Record<string, unknown>).holidays, 1);

  const other = await views.getEmployeeCalendar(admin, 'emp-2', '2026-10');
  const otherDays = other.days as Array<Record<string, unknown>>;
  assert.equal(otherDays.find((day) => day.date === '2026-10-09')?.holidayName, 'Holiday branch-2');
  assert.equal((other.summary as Record<string, unknown>).holidays, 1);
});

test('monthly summaries apply branch holidays and still count every day once', async () => {
  const { store, views } = service();
  seedBranchHoliday(store, 'holiday-a', 'branch-1');
  const own = (await views.getSummary(employeeCaller, '2026-10')) as Record<string, unknown>;
  const other = (await views.getSummary(admin, '2026-10', 'emp-2')) as Record<string, unknown>;
  const ownSummary = own.summary as Record<string, number>;
  const otherSummary = other.summary as Record<string, number>;
  assert.equal(ownSummary.holidays, 1);
  assert.equal(otherSummary.holidays, 0);
  for (const summary of [ownSummary, otherSummary]) {
    assert.equal(summary.present + summary.halfDays + summary.absent + summary.paidLeave + summary.unpaidLeave + summary.weeklyOffs + summary.holidays + summary.notJoinedOrLeftDays + summary.pending, summary.daysInMonth);
  }
});

test('two pre-existing same-date holidays remain one summary day', async () => {
  const { store, views } = service();
  store.holidays.set('2026-10-02', {
    id: '2026-10-02', name: 'Old date-keyed holiday',
  } as unknown as HolidayRecord);
  store.holidays.set('old-generated-id', {
    id: 'old-generated-id', date: '2026-10-02', name: 'Older duplicate',
  } as unknown as HolidayRecord);

  const calendar = await views.getMyCalendar(employeeCaller, '2026-10');
  const days = calendar.days as Array<Record<string, unknown>>;
  const duplicateDay = days.find((day) => day.date === '2026-10-02');
  assert.equal(duplicateDay?.status, 'HOLIDAY');
  assert.match(String(duplicateDay?.holidayName), /Old date-keyed holiday/);
  assert.match(String(duplicateDay?.holidayName), /Older duplicate/);

  const response = await views.getSummary(employeeCaller, '2026-10') as Record<string, unknown>;
  const summary = response.summary as Record<string, number>;
  assert.equal(summary.holidays, 1);
  assert.equal(
    summary.present + summary.halfDays + summary.absent + summary.paidLeave +
      summary.unpaidLeave + summary.weeklyOffs + summary.holidays +
      summary.notJoinedOrLeftDays + summary.pending,
    summary.daysInMonth,
  );
});

test('admin by-date status uses each employee primary branch holiday', async () => {
  const { store, views } = service();
  seedBranchHoliday(store, 'holiday-a', 'branch-1');
  const result = await views.getByDate(admin, '2026-10-09');
  const rows = result.rows as Array<Record<string, unknown>>;
  assert.equal(rows.find((row) => row.empId === 'emp-1')?.status, 'HOLIDAY');
  assert.equal(rows.find((row) => row.empId === 'emp-2')?.status, 'A');
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

test('calendar names leave types and reads the type list once for a multi-employee summary', async () => {
  const { store, views } = service();
  store.leaveTypes.push({
    id: 'unpaid', name: 'Unpaid Leave', code: 'UL', paid: false,
    annualQuotaDays: null, allowHalfDay: true, status: 'active', system: true, sortOrder: 2,
  });
  store.attendance.set('2026-10_emp-1', {
    empId: 'emp-1', month: '2026-10', days: {
      '2026-10-05': { status: 'L', leaveTypeId: 'annual' },
      '2026-10-06': { status: 'UL', leaveTypeId: 'unpaid' },
      '2026-10-07': { halfLeave: {
        session: 'first_half', paid: true, leaveTypeId: 'annual', leaveRequestId: 'half-1',
      } },
    },
  });
  const calendar = await views.getMyCalendar(employeeCaller, '2026-10');
  const days = calendar.days as Array<Record<string, unknown>>;
  assert.equal(days[4]?.leaveTypeName, 'Annual Leave');
  assert.equal(days[5]?.leaveTypeName, 'Unpaid Leave');
  assert.equal(days[6]?.status, 'HL');
  assert.equal((days[6]?.halfLeave as Record<string, unknown>).leaveTypeName, 'Annual Leave');
  assert.equal(store.leaveTypeReads, 1);

  store.leaveTypeReads = 0;
  await views.getSummary(admin, '2026-10');
  assert.equal(store.leaveTypeReads, 1);
});

test('by-date rows and totals include HL marker-only days', async () => {
  const { store, views } = service();
  store.attendance.set('2026-10_emp-1', {
    empId: 'emp-1', month: '2026-10', days: {
      '2026-10-09': { halfLeave: {
        session: 'second_half', paid: false, leaveTypeId: 'unpaid', leaveRequestId: 'half-2',
      } },
    },
  });
  const result = await views.getByDate(admin, '2026-10-09');
  const rows = result.rows as Array<Record<string, unknown>>;
  const row = rows.find((item) => item.empId === 'emp-1')!;
  assert.equal(row.status, 'HL');
  assert.equal(row.otherHalf, 'absent');
  assert.equal(result.totals.HL, 1);
  assert.equal(store.leaveTypeReads, 1);
});

test('admin edit preserves a marker-only day and does not require its prior status', async () => {
  const { store, views } = service();
  const marker = { session: 'first_half', paid: true, leaveTypeId: 'annual', leaveRequestId: 'half-3' };
  store.attendance.set('2026-10_emp-1', {
    empId: 'emp-1', month: '2026-10', days: { '2026-10-09': { halfLeave: marker } },
  });
  const edited = await views.editAttendance({
    caller: admin, empId: 'emp-1', date: '2026-10-09', status: 'A', reason: 'Absence edit',
  });
  assert.equal(edited.status, 'HL');
  assert.deepEqual(store.attendance.get('2026-10_emp-1')?.days['2026-10-09']?.halfLeave, marker);
  assert.equal(store.attendance.get('2026-10_emp-1')?.days['2026-10-09']?.status, 'A');
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
