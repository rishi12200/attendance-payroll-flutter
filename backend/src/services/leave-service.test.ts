import assert from 'node:assert/strict';
import test from 'node:test';
import { Timestamp } from 'firebase-admin/firestore';
import { buildMonthCalendar } from '../domain/attendance-calendar';
import { AppError } from '../errors/app-error';
import type { AttendanceDay, AttendanceDocument } from './attendance-store';
import type { EmployeeRecord } from './employee-service';
import { LeaveService } from './leave-service';
import type {
  LeaveAuditRecord,
  LeaveRequestRecord,
  LeaveStore,
  LeaveTransaction,
} from './leave-store';

const employee: EmployeeRecord = {
  uid: 'emp-1',
  role: 'employee',
  status: 'active',
  empCode: 'EMP001',
  name: 'Asha',
  designation: 'Associate',
  doj: '2026-01-01',
  dol: null,
};
const empCaller = { uid: 'emp-1', role: 'employee' };
const otherCaller = { uid: 'emp-2', role: 'employee' };
const admin = { uid: 'admin-1', role: 'admin' };
const timestamp = Timestamp.fromDate(new Date('2026-10-10T10:00:00.000Z'));

class FakeLeaveStore implements LeaveStore {
  readonly employees = new Map<string, EmployeeRecord>([
    ['emp-1', { ...employee }],
    ['emp-2', { ...employee, uid: 'emp-2', empCode: 'EMP002', name: 'Ravi' }],
  ]);
  readonly requests = new Map<string, LeaveRequestRecord>();
  readonly attendance = new Map<string, AttendanceDocument>();
  readonly payrollMonths = new Map<string, { locked?: boolean }>();
  readonly holidays = new Set<string>();
  readonly audits: LeaveAuditRecord[] = [];
  readonly events: string[] = [];
  settings: Record<string, unknown> = { weeklyOffDays: [] };
  listLimit = 0;
  private nextId = 1;
  private tail: Promise<void> = Promise.resolve();

  serverTimestamp() {
    return timestamp;
  }

  async getLeaveRequest(id: string) {
    return this.requests.get(id);
  }

  async listLeaveRequests(input: { empId?: string; limit: number }) {
    this.listLimit = input.limit;
    return [...this.requests.values()]
      .filter((request) => input.empId === undefined || request.empId === input.empId)
      .slice(0, input.limit);
  }

  async getEmployee(uid: string) {
    return this.employees.get(uid);
  }

  async runTransaction<T>(work: (transaction: LeaveTransaction) => Promise<T>): Promise<T> {
    const previous = this.tail;
    let release!: () => void;
    this.tail = new Promise<void>((resolve) => (release = resolve));
    await previous;
    let wrote = false;
    const requestCreates: LeaveRequestRecord[] = [];
    const requestUpdates: Array<{ id: string; changes: Record<string, unknown> }> = [];
    const attendanceWrites: Array<{
      id: string;
      empId: string;
      month: string;
      date: string;
      day: AttendanceDay;
    }> = [];
    const auditWrites: LeaveAuditRecord[] = [];
    const read = <T>(workRead: () => T): T => {
      assert.equal(wrote, false, 'transaction attempted a read after a write');
      return workRead();
    };
    const tx: LeaveTransaction = {
      getLeaveRequest: async (id) => read(() => {
        this.events.push('read-request');
        return this.requests.get(id);
      }),
      getEmployee: async (uid) => read(() => {
        this.events.push('read-employee');
        return this.employees.get(uid);
      }),
      getCompanySettings: async () => read(() => {
        this.events.push('read-settings');
        return this.settings;
      }),
      getHolidays: async (months) => read(() => {
        this.events.push('read-holidays');
        return [...this.holidays].filter((date) => months.includes(date.slice(0, 7)));
      }),
      getAttendance: async (id) => read(() => {
        this.events.push('read-attendance');
        return this.attendance.get(id);
      }),
      getPayrollMonth: async (month) => read(() => {
        this.events.push('read-payroll');
        return this.payrollMonths.get(month);
      }),
      getEmployeeLeaveRequests: async (empId) => read(() => {
        this.events.push('read-employee-leaves');
        return [...this.requests.values()].filter((request) => request.empId === empId);
      }),
      createLeaveRequest: (record) => {
        wrote = true;
        this.events.push('create-request');
        const id = `leave-${this.nextId++}`;
        requestCreates.push({ ...record, id } as LeaveRequestRecord);
        return id;
      },
      updateLeaveRequest: (id, changes) => {
        wrote = true;
        this.events.push('update-request');
        requestUpdates.push({ id, changes });
      },
      setAttendanceDay: (write) => {
        wrote = true;
        this.events.push('write-attendance');
        attendanceWrites.push(write);
      },
      createAudit: (audit) => {
        wrote = true;
        this.events.push('write-audit');
        auditWrites.push(audit);
      },
    };
    try {
      const result = await work(tx);
      for (const created of requestCreates) this.requests.set(created.id, created);
      for (const { id, changes } of requestUpdates) {
        const request = this.requests.get(id);
        assert.ok(request, `request ${id} must exist for an update`);
        this.requests.set(id, { ...request, ...changes } as LeaveRequestRecord);
      }
      for (const write of attendanceWrites) {
        const current = this.attendance.get(write.id) ?? {
          empId: write.empId,
          month: write.month,
          days: {},
        };
        this.attendance.set(write.id, {
          ...current,
          days: { ...current.days, [write.date]: write.day },
        });
      }
      this.audits.push(...auditWrites);
      return result;
    } finally {
      release();
    }
  }

  seedRequest(input: Partial<LeaveRequestRecord> & Pick<LeaveRequestRecord, 'id' | 'fromDate' | 'toDate'>) {
    this.requests.set(input.id, {
      id: input.id,
      empId: input.empId ?? 'emp-1',
      fromDate: input.fromDate,
      toDate: input.toDate,
      reason: input.reason ?? 'Reason',
      status: input.status ?? 'pending',
      createdAt: input.createdAt ?? timestamp,
      updatedAt: input.updatedAt ?? timestamp,
    } as LeaveRequestRecord);
  }
}

function service() {
  const store = new FakeLeaveStore();
  return { store, leaves: new LeaveService(store) };
}

async function expectError(work: Promise<unknown>, status: number, code: string) {
  await assert.rejects(work, (error: unknown) => {
    assert.ok(error instanceof AppError);
    assert.equal(error.status, status);
    assert.equal(error.code, code);
    return true;
  });
}

async function apply(leaves: LeaveService, fromDate = '2026-10-05', toDate = fromDate) {
  return leaves.apply(empCaller, { fromDate, toDate, reason: 'Family event' });
}

async function pendingRequest(leaves: LeaveService, fromDate: string, toDate: string) {
  return apply(leaves, fromDate, toDate);
}

test('applies a pending request and enforces the employee joining window', async () => {
  const { store, leaves } = service();
  const result = await apply(leaves, '2026-10-05', '2026-10-06');
  assert.equal(result.status, 'pending');
  assert.equal(result.reason, 'Family event');
  assert.equal(result.createdAt, timestamp);
  assert.equal(store.listLimit, 0);

  await expectError(apply(leaves, '2025-12-31'), 422, 'OUTSIDE_EMPLOYMENT_WINDOW');
  store.employees.set('emp-1', { ...employee, dol: '2026-10-05' });
  await expectError(apply(leaves, '2026-10-06'), 422, 'OUTSIDE_EMPLOYMENT_WINDOW');
});

test('rejects admins, inactive employees, locked months and overlapping requests', async () => {
  const { store, leaves } = service();
  await expectError(
    leaves.apply(admin, { fromDate: '2026-10-05', toDate: '2026-10-05', reason: 'x' }),
    403,
    'FORBIDDEN',
  );
  store.employees.set('emp-1', { ...employee, status: 'inactive' });
  await expectError(apply(leaves), 403, 'FORBIDDEN');
  store.employees.set('emp-1', { ...employee });

  store.payrollMonths.set('2026-10', { locked: true });
  await expectError(apply(leaves), 409, 'MONTH_LOCKED');
  store.payrollMonths.clear();

  store.seedRequest({ id: 'pending', fromDate: '2026-10-05', toDate: '2026-10-06' });
  await assert.rejects(apply(leaves, '2026-10-06'), (error: unknown) => {
    assert.ok(error instanceof AppError);
    assert.equal(error.code, 'LEAVE_OVERLAP');
    assert.deepEqual(error.details, { requestId: 'pending' });
    return true;
  });
  store.requests.clear();
  store.seedRequest({ id: 'approved', fromDate: '2026-10-05', toDate: '2026-10-06', status: 'approved' });
  await expectError(apply(leaves, '2026-10-06'), 409, 'LEAVE_OVERLAP');
});

test('adjacent, rejected and cancelled requests do not block a new request', async () => {
  const { store, leaves } = service();
  store.seedRequest({ id: 'adjacent', fromDate: '2026-10-01', toDate: '2026-10-04' });
  store.seedRequest({ id: 'rejected', fromDate: '2026-10-05', toDate: '2026-10-06', status: 'rejected' });
  store.seedRequest({ id: 'cancelled', fromDate: '2026-10-05', toDate: '2026-10-06', status: 'cancelled' });
  const result = await apply(leaves, '2026-10-05', '2026-10-06');
  assert.equal(result.status, 'pending');
});

test('lists own and admin requests with filters, newest order and employee details', async () => {
  const { store, leaves } = service();
  store.seedRequest({ id: 'old', fromDate: '2026-10-01', toDate: '2026-10-01', createdAt: new Date('2026-10-01T00:00:00Z') });
  store.seedRequest({ id: 'new', fromDate: '2026-10-02', toDate: '2026-10-02', createdAt: new Date('2026-10-02T00:00:00Z') });
  store.seedRequest({ id: 'other', empId: 'emp-2', fromDate: '2026-10-03', toDate: '2026-10-03' });
  const mine = await leaves.listMine(empCaller, 'all');
  assert.deepEqual(mine.map((request) => request.id), ['new', 'old']);
  assert.equal(store.listLimit, 200);
  const adminList = await leaves.listAll(admin, { status: 'all' });
  assert.equal(adminList.length, 3);
  assert.equal(adminList.find((request) => request.id === 'new')?.name, 'Asha');
  assert.equal(adminList.find((request) => request.id === 'other')?.designation, 'Associate');
  await expectError(leaves.listAll(empCaller, { status: 'all' }), 403, 'FORBIDDEN');
  assert.equal((await leaves.getById(empCaller, 'new')).id, 'new');
  await expectError(leaves.getById(otherCaller, 'new'), 404, 'LEAVE_NOT_FOUND');
  assert.equal((await leaves.getById(admin, 'new')).id, 'new');
});

test('cancels only the caller own pending requests', async () => {
  const { store, leaves } = service();
  store.seedRequest({ id: 'mine', fromDate: '2026-10-05', toDate: '2026-10-05' });
  const cancelled = await leaves.cancel(empCaller, 'mine');
  assert.equal(cancelled.status, 'cancelled');
  assert.equal(cancelled.updatedAt, timestamp);
  store.seedRequest({ id: 'other', empId: 'emp-2', fromDate: '2026-10-05', toDate: '2026-10-05' });
  await expectError(leaves.cancel(empCaller, 'other'), 404, 'LEAVE_NOT_FOUND');
  await expectError(leaves.cancel(empCaller, 'mine'), 409, 'NOT_PENDING');
});

test('approves paid and unpaid requests into L and UL attendance days with audit', async () => {
  for (const leaveType of ['paid', 'unpaid'] as const) {
    const { store, leaves } = service();
    const request = await pendingRequest(leaves, '2026-10-05', '2026-10-06');
    store.attendance.set('2026-10_emp-1', {
      empId: 'emp-1', month: '2026-10',
      days: { '2026-10-05': { status: 'A', note: 'old absent' } },
    });
    const result = await leaves.decide({
      caller: admin,
      id: request.id,
      decision: 'approved',
      leaveType,
      note: 'Approved by manager',
    });
    assert.equal(result.status, 'approved');
    assert.deepEqual(result.writtenDates, ['2026-10-05', '2026-10-06']);
    assert.deepEqual(result.skippedDates, []);
    assert.equal(result.leaveType, leaveType);
    assert.equal(result.decisionNote, 'Approved by manager');
    const expected = leaveType === 'paid' ? 'L' : 'UL';
    assert.equal(store.attendance.get('2026-10_emp-1')?.days['2026-10-05']?.status, expected);
    assert.equal(store.attendance.get('2026-10_emp-1')?.days['2026-10-05']?.source, 'leave');
    assert.equal(store.attendance.get('2026-10_emp-1')?.days['2026-10-05']?.leaveRequestId, request.id);
    assert.equal(store.attendance.get('2026-10_emp-1')?.days['2026-10-05']?.editedBy, admin.uid);
    assert.equal(store.audits.length, 1);
    assert.equal(store.audits[0]?.requestId, request.id);
    assert.equal(store.audits[0]?.leaveType, leaveType);
    assert.ok(store.audits[0]?.at instanceof Timestamp);
    const decisionWrite = store.events.indexOf('write-attendance');
    assert.ok(store.events.slice(0, decisionWrite).includes('read-settings'));
    assert.ok(store.events.slice(0, decisionWrite).includes('read-holidays'));
    assert.ok(store.events.slice(0, decisionWrite).includes('read-payroll'));
  }
});

test('skips weekly offs, holidays and punches while overwriting admin absence', async () => {
  const { store, leaves } = service();
  store.settings = { weeklyOffDays: [0] };
  store.holidays.add('2026-10-06');
  store.attendance.set('2026-10_emp-1', {
    empId: 'emp-1', month: '2026-10',
    days: {
      '2026-10-05': { status: 'P', inTime: timestamp },
      '2026-10-07': { status: 'A', source: 'admin_edit' },
    },
  });
  const request = await pendingRequest(leaves, '2026-10-04', '2026-10-07');
  const result = await leaves.decide({ caller: admin, id: request.id, decision: 'approved', leaveType: 'paid' });
  assert.deepEqual(result.writtenDates, ['2026-10-07']);
  assert.deepEqual(result.skippedDates, [
    { date: '2026-10-04', reason: 'weekly_off' },
    { date: '2026-10-05', reason: 'has_punch' },
    { date: '2026-10-06', reason: 'holiday' },
  ]);
  assert.equal(store.attendance.get('2026-10_emp-1')?.days['2026-10-07']?.status, 'L');
});

test('writes across two months and creates missing attendance month documents', async () => {
  const { store, leaves } = service();
  const request = await pendingRequest(leaves, '2026-12-30', '2027-01-02');
  const result = await leaves.decide({ caller: admin, id: request.id, decision: 'approved', leaveType: 'unpaid' });
  assert.equal(result.writtenDates?.length, 4);
  assert.deepEqual([...store.attendance.keys()].sort(), ['2026-12_emp-1', '2027-01_emp-1']);
  assert.equal(store.attendance.get('2026-12_emp-1')?.days['2026-12-30']?.status, 'UL');
  assert.equal(store.attendance.get('2027-01_emp-1')?.days['2027-01-02']?.status, 'UL');
});

test('locked approval writes nothing; rejection changes only the request', async () => {
  const locked = service();
  const lockedRequest = await pendingRequest(locked.leaves, '2026-10-05', '2026-11-02');
  locked.store.payrollMonths.set('2026-11', { locked: true });
  await expectError(locked.leaves.decide({ caller: admin, id: lockedRequest.id, decision: 'approved', leaveType: 'paid' }), 409, 'MONTH_LOCKED');
  assert.equal(locked.store.requests.get(lockedRequest.id)?.status, 'pending');
  assert.equal(locked.store.attendance.size, 0);
  assert.equal(locked.store.audits.length, 0);

  const rejected = service();
  const rejectedRequest = await pendingRequest(rejected.leaves, '2026-10-05');
  const response = await rejected.leaves.decide({ caller: admin, id: rejectedRequest.id, decision: 'rejected', note: 'Insufficient coverage' });
  assert.equal(response.status, 'rejected');
  assert.equal(response.decisionNote, 'Insufficient coverage');
  assert.equal(rejected.store.attendance.size, 0);
  assert.equal(rejected.store.audits.length, 0);
});

test('rejects repeated decisions including concurrent approvals', async () => {
  const { leaves } = service();
  const request = await pendingRequest(leaves, '2026-10-05');
  const [first, second] = await Promise.allSettled([
    leaves.decide({ caller: admin, id: request.id, decision: 'approved', leaveType: 'paid' }),
    leaves.decide({ caller: { uid: 'admin-2', role: 'admin' }, id: request.id, decision: 'approved', leaveType: 'paid' }),
  ]);
  assert.equal(first.status, 'fulfilled');
  assert.equal(second.status, 'rejected');
  if (second.status === 'rejected') {
    assert.ok(second.reason instanceof AppError);
    assert.equal(second.reason.code, 'ALREADY_DECIDED');
  }
});

test('approves all-skipped requests with a warning and calendar summaries reflect leave', async () => {
  const { store, leaves } = service();
  store.settings = { weeklyOffDays: [0] };
  const allSkipped = await pendingRequest(leaves, '2026-10-04');
  const warning = await leaves.decide({ caller: admin, id: allSkipped.id, decision: 'approved', leaveType: 'paid' });
  assert.equal(warning.noDaysWritten, true);
  assert.deepEqual(warning.writtenDates, []);

  for (const leaveType of ['paid', 'unpaid'] as const) {
    const instance = service();
    instance.store.settings = { weeklyOffDays: [] };
    const leave = await pendingRequest(instance.leaves, '2028-02-01');
    await instance.leaves.decide({ caller: admin, id: leave.id, decision: 'approved', leaveType });
    const days = Object.fromEntries(
      [...instance.store.attendance.values()].flatMap((document) => Object.entries(document.days)),
    );
    const calendar = buildMonthCalendar({
      month: '2028-02', today: '2028-02-01', days,
      holidays: {}, weeklyOffDays: [],
    });
    assert.equal(calendar.days[0]?.status, leaveType === 'paid' ? 'L' : 'UL');
    assert.equal(calendar.days[0]?.source, 'leave');
    assert.equal(calendar.days[0]?.leaveRequestId, leave.id);
    assert.equal(calendar.summary.paidLeave, leaveType === 'paid' ? 1 : 0);
    assert.equal(calendar.summary.unpaidLeave, leaveType === 'unpaid' ? 1 : 0);
    assert.equal(calendar.summary.lop, leaveType === 'paid' ? 0 : 1);
  }
});
