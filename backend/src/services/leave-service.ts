import { AppError } from '../errors/app-error';
import { attendanceSettingsFromDocument } from '../domain/attendance';
import {
  classifyLeaveDates,
  expandDateRange,
  monthsTouched,
  rangesOverlap,
} from '../domain/leave';
import type { EmployeeRecord } from './employee-service';
import type {
  LeaveRequestRecord,
  LeaveStatus,
  LeaveStore,
  LeaveType,
} from './leave-store';

const MAX_LIST_READS = 200;
const activeStatuses = new Set<LeaveStatus>(['pending', 'approved']);

export interface LeaveCaller {
  uid: string;
  role: string;
}

export interface LeaveServiceDependencies {
  store: LeaveStore;
}

export class LeaveService {
  constructor(private readonly store: LeaveStore) {}

  async apply(
    caller: LeaveCaller,
    input: { fromDate: string; toDate: string; reason: string },
  ): Promise<LeaveRequestRecord> {
    const employee = await this.requireActiveEmployee(caller);
    const dates = this.expandRequest(input.fromDate, input.toDate);
    this.assertWithinEmploymentWindow(employee, input.fromDate, input.toDate);
    const months = monthsTouched(input.fromDate, input.toDate);

    const id = await this.store.runTransaction(async (transaction) => {
      const [currentEmployee, lockedMonths, requests] = await Promise.all([
        transaction.getEmployee(caller.uid),
        Promise.all(months.map((month) => transaction.getPayrollMonth(month))),
        transaction.getEmployeeLeaveRequests(caller.uid),
      ]);
      if (!currentEmployee || currentEmployee.role !== 'employee' || currentEmployee.status !== 'active') {
        throw new AppError(403, 'FORBIDDEN', 'An active employee account is required.');
      }
      this.assertWithinEmploymentWindow(currentEmployee, input.fromDate, input.toDate);
      const lockedIndex = lockedMonths.findIndex((month) => month?.locked === true);
      if (lockedIndex >= 0) throw this.monthLocked(months[lockedIndex]!);

      const conflict = requests.find((request) =>
        activeStatuses.has(request.status) &&
        rangesOverlap(input.fromDate, input.toDate, request.fromDate, request.toDate),
      );
      if (conflict) {
        throw new AppError(
          409,
          'LEAVE_OVERLAP',
          'This leave request overlaps an existing pending or approved request.',
          { requestId: conflict.id },
        );
      }

      const timestamp = this.store.serverTimestamp();
      return transaction.createLeaveRequest({
        empId: caller.uid,
        fromDate: dates[0]!,
        toDate: dates[dates.length - 1]!,
        reason: input.reason.trim(),
        status: 'pending',
        createdAt: timestamp,
        updatedAt: timestamp,
      });
    });
    return this.requirePersistedRequest(id);
  }

  async listMine(
    caller: LeaveCaller,
    status?: LeaveStatus | 'all',
  ): Promise<LeaveRequestRecord[]> {
    await this.requireActiveEmployee(caller);
    const requests = await this.store.listLeaveRequests({
      empId: caller.uid,
      limit: MAX_LIST_READS,
    });
    return sortNewestFirst(requests.filter((request) => status === undefined || status === 'all' || request.status === status));
  }

  async listAll(
    caller: LeaveCaller,
    input: { status: LeaveStatus | 'all'; empId?: string },
  ): Promise<Array<Record<string, unknown>>> {
    this.requireRole(caller.role, 'admin');
    const requests = await this.store.listLeaveRequests({
      empId: input.empId,
      limit: MAX_LIST_READS,
    });
    const matching = sortNewestFirst(requests.filter((request) =>
      (input.status === 'all' || request.status === input.status) &&
      (input.empId === undefined || request.empId === input.empId),
    ));
    const employees = await Promise.all(
      [...new Set(matching.map((request) => request.empId))].map((id) => this.store.getEmployee(id)),
    );
    const byId = new Map<string, EmployeeRecord | undefined>();
    [...new Set(matching.map((request) => request.empId))].forEach((id, index) => byId.set(id, employees[index]));
    return matching.map((request) => {
      const employee = byId.get(request.empId);
      return {
        ...request,
        name: employee?.name ?? '',
        empCode: employee?.empCode ?? null,
        designation: employee?.designation ?? '',
      };
    });
  }

  async getById(caller: LeaveCaller, id: string): Promise<LeaveRequestRecord> {
    if (caller.role !== 'admin' && caller.role !== 'employee') {
      throw this.forbidden();
    }
    const request = await this.store.getLeaveRequest(id);
    if (!request || (caller.role === 'employee' && request.empId !== caller.uid)) {
      throw new AppError(404, 'LEAVE_NOT_FOUND', 'Leave request was not found.');
    }
    return request;
  }

  async cancel(caller: LeaveCaller, id: string): Promise<LeaveRequestRecord> {
    await this.requireActiveEmployee(caller);
    await this.store.runTransaction(async (transaction) => {
      const request = await transaction.getLeaveRequest(id);
      if (!request || request.empId !== caller.uid) {
        throw new AppError(404, 'LEAVE_NOT_FOUND', 'Leave request was not found.');
      }
      if (request.status !== 'pending') {
        throw new AppError(409, 'NOT_PENDING', 'Only pending leave requests can be cancelled.');
      }
      transaction.updateLeaveRequest(id, {
        status: 'cancelled',
        updatedAt: this.store.serverTimestamp(),
      });
    });
    return this.requirePersistedRequest(id);
  }

  async decide(input: {
    caller: LeaveCaller;
    id: string;
    decision: 'approved' | 'rejected';
    leaveType?: LeaveType;
    note?: string;
  }): Promise<LeaveRequestRecord & { noDaysWritten?: true }> {
    this.requireRole(input.caller.role, 'admin');
    const noDaysWritten = await this.store.runTransaction(async (transaction) => {
      const request = await transaction.getLeaveRequest(input.id);
      if (!request) throw new AppError(404, 'LEAVE_NOT_FOUND', 'Leave request was not found.');
      if (request.status !== 'pending') {
        throw new AppError(409, 'ALREADY_DECIDED', 'This leave request is no longer pending.');
      }

      const range = this.expandRequest(request.fromDate, request.toDate);
      const months = monthsTouched(request.fromDate, request.toDate);
      const [employee, settingsDocument] = await Promise.all([
        transaction.getEmployee(request.empId),
        transaction.getCompanySettings(),
      ]);
      if (!employee || employee.role !== 'employee') {
        throw new AppError(404, 'EMPLOYEE_NOT_FOUND', 'Employee was not found.');
      }

      const ids = months.map((month) => attendanceId(month, request.empId));
      const [holidayDates, attendanceDocuments, payrollMonths] = await Promise.all([
        transaction.getHolidays(months),
        Promise.all(ids.map((id) => transaction.getAttendance(id))),
        Promise.all(months.map((month) => transaction.getPayrollMonth(month))),
      ]);

      if (input.decision === 'rejected') {
        transaction.updateLeaveRequest(input.id, {
          status: 'rejected',
          decidedBy: input.caller.uid,
          decidedAt: this.store.serverTimestamp(),
          decisionNote: input.note,
          updatedAt: this.store.serverTimestamp(),
        });
        return false;
      }

      const lockedIndex = payrollMonths.findIndex((month) => month?.locked === true);
      if (lockedIndex >= 0) throw this.monthLocked(months[lockedIndex]!);
      const settings = attendanceSettingsFromDocument(settingsDocument);
      const days: Record<string, { status?: unknown }> = {};
      attendanceDocuments.forEach((document) => {
        if (document) {
          for (const [date, day] of Object.entries(document.days)) {
            days[date] = { status: day.status };
          }
        }
      });
      const classification = classifyLeaveDates({
        dates: range,
        doj: typeof employee.doj === 'string' ? employee.doj : null,
        dol: typeof employee.dol === 'string' ? employee.dol : null,
        holidays: new Set(holidayDates),
        weeklyOffDays: settings.weeklyOffDays,
        days,
      });
      const timestamp = this.store.serverTimestamp();
      for (const date of classification.toWrite) {
        const month = date.slice(0, 7);
        transaction.setAttendanceDay({
          id: attendanceId(month, request.empId),
          empId: request.empId,
          month,
          date,
          day: {
            status: input.leaveType === 'paid' ? 'L' : 'UL',
            source: 'leave',
            leaveRequestId: input.id,
            editedBy: input.caller.uid,
            editedAt: timestamp,
          },
        });
      }
      transaction.updateLeaveRequest(input.id, {
        status: 'approved',
        leaveType: input.leaveType,
        writtenDates: classification.toWrite,
        skippedDates: classification.skipped,
        decidedBy: input.caller.uid,
        decidedAt: timestamp,
        decisionNote: input.note,
        updatedAt: timestamp,
      });
      transaction.createAudit({
        action: 'leave.decision',
        requestId: input.id,
        empId: request.empId,
        decision: 'approved',
        leaveType: input.leaveType,
        writtenDates: classification.toWrite,
        skippedDates: classification.skipped,
        by: input.caller.uid,
        at: timestamp,
      });
      return classification.toWrite.length === 0;
    });

    const request = await this.requirePersistedRequest(input.id);
    return noDaysWritten ? { ...request, noDaysWritten: true } : request;
  }

  private async requirePersistedRequest(id: string): Promise<LeaveRequestRecord> {
    const request = await this.store.getLeaveRequest(id);
    if (!request) throw new AppError(404, 'LEAVE_NOT_FOUND', 'Leave request was not found.');
    return request;
  }

  private async requireActiveEmployee(caller: LeaveCaller): Promise<EmployeeRecord> {
    this.requireRole(caller.role, 'employee');
    const employee = await this.store.getEmployee(caller.uid);
    if (!employee || employee.role !== 'employee' || employee.status !== 'active') {
      throw new AppError(403, 'FORBIDDEN', 'An active employee account is required.');
    }
    return employee;
  }

  private assertWithinEmploymentWindow(
    employee: EmployeeRecord,
    fromDate: string,
    toDate: string,
  ): void {
    if (
      (typeof employee.doj === 'string' && fromDate < employee.doj) ||
      (typeof employee.dol === 'string' && toDate > employee.dol)
    ) {
      throw new AppError(
        422,
        'OUTSIDE_EMPLOYMENT_WINDOW',
        'Leave dates must fall within the employee joining window.',
      );
    }
  }

  private expandRequest(fromDate: string, toDate: string): string[] {
    const result = expandDateRange(fromDate, toDate);
    if (!result.ok) {
      if (result.reason === 'range_too_long') {
        throw new AppError(422, 'LEAVE_RANGE_TOO_LONG', 'A leave request cannot exceed 31 days.');
      }
      throw new AppError(400, 'INVALID_DATE_RANGE', 'Leave dates must be valid and fromDate must not be after toDate.');
    }
    return result.dates;
  }

  private monthLocked(month: string): AppError {
    return new AppError(409, 'MONTH_LOCKED', `Leave cannot be changed because ${month} is locked.`, { month });
  }

  private requireRole(actual: string, expected: 'admin' | 'employee'): void {
    if (actual !== expected) throw this.forbidden();
  }

  private forbidden(): AppError {
    return new AppError(403, 'FORBIDDEN', 'You do not have permission to access this resource.');
  }
}

function attendanceId(month: string, empId: string): string {
  return `${month}_${empId}`;
}

function sortNewestFirst(requests: LeaveRequestRecord[]): LeaveRequestRecord[] {
  return [...requests].sort((left, right) => timestampValue(right.createdAt) - timestampValue(left.createdAt));
}

function timestampValue(value: unknown): number {
  if (value instanceof Date) return value.getTime();
  if (typeof value === 'string' || typeof value === 'number') return Date.parse(String(value)) || 0;
  if (typeof value === 'object' && value !== null && 'toDate' in value && typeof value.toDate === 'function') {
    const date = value.toDate();
    return date instanceof Date ? date.getTime() : 0;
  }
  return 0;
}
