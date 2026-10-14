import { AppError } from '../errors/app-error';
import { attendanceSettingsFromDocument } from '../domain/attendance';
import {
  classifyLeaveDates,
  classifyHalfLeaveDate,
  expandDateRange,
  monthsTouched,
  rangesOverlap,
} from '../domain/leave';
import type { EmployeeRecord } from './employee-service';
import type {
  LeaveRequestRecord,
  LeaveStatus,
  LeaveStore,
} from './leave-store';
import { holidayAppliesToBranch } from '../domain/holidays';
import { computeBalances, countRequestedDates, dayWeight, splitByLeaveYear, wouldExceedQuota, type LeaveSession } from '../domain/leave-quantity';
import { leaveYearByYear, leaveYearOf } from '../domain/leave-year';
import { todayIST } from '../domain/dates';

const MAX_LIST_READS = 200;
const activeStatuses = new Set<LeaveStatus>(['pending', 'approved']);

export interface LeaveCaller {
  uid: string;
  role: string;
}

export interface LeaveServiceDependencies {
  store: LeaveStore;
}

export type LeaveDto = Pick<LeaveRequestRecord,
  'id' | 'empId' | 'fromDate' | 'toDate' | 'reason' | 'status' | 'createdAt' | 'updatedAt'
> & Pick<LeaveRequestRecord, 'leaveTypeId' | 'leaveTypeName' | 'paid' | 'session'> & Partial<Pick<LeaveRequestRecord,
  'leaveType' | 'decidedBy' | 'decidedAt' | 'decisionNote' | 'writtenDates' | 'skippedDates' | 'requestedDates' | 'requestedDays' | 'writtenDays'
>>;

export class LeaveService {
  constructor(private readonly store: LeaveStore) {}

  async getBalance(caller: LeaveCaller, input: { year?: number; empId?: string }): Promise<Record<string, unknown>> {
    if (caller.role !== 'employee' && caller.role !== 'admin') throw this.forbidden();
    let empId: string;
    if (caller.role === 'employee') {
      if (input.empId !== undefined && input.empId !== caller.uid) throw this.forbidden();
      await this.requireActiveEmployee(caller);
      empId = caller.uid;
    } else {
      if (!input.empId) throw new AppError(403, 'FORBIDDEN', 'Admin accounts must select an employee to view leave balances.');
      const employee = await this.store.getEmployee(input.empId);
      if (!employee || employee.role !== 'employee') {
        throw new AppError(404, 'EMPLOYEE_NOT_FOUND', 'Employee was not found.');
      }
      empId = input.empId;
    }
    if (input.year !== undefined && (!Number.isInteger(input.year) || input.year < 2000 || input.year > 2100)) {
      throw new AppError(400, 'VALIDATION_ERROR', 'Leave balance year must be from 2000 to 2100.');
    }
    const [settingsDocument, types, requests] = await Promise.all([
      this.store.getCompanySettings(),
      this.store.listLeaveTypes(),
      this.store.listLeaveRequests({ empId, limit: 500 }),
    ]);
    const settings = attendanceSettingsFromDocument(settingsDocument);
    const today = todayIST();
    const currentYear = leaveYearOf(today, settings.leaveYearStartMonth).year;
    const year = input.year ?? currentYear;
    const yearDetails = leaveYearByYear(year, settings.leaveYearStartMonth);
    const balances = computeBalances({
      types,
      requests,
      yearStartDate: yearDetails.startDate,
      yearEndDate: yearDetails.endDate,
    });
    const balanceById = new Map(balances.map((balance) => [balance.leaveTypeId, balance]));
    const visibleTypes = types
      .filter((type) => {
        const balance = balanceById.get(type.id);
        return (type.status === 'active' && type.id !== 'legacy-paid') ||
          (balance !== undefined && (balance.used > 0 || balance.pending > 0));
      })
      .sort((left, right) => left.sortOrder - right.sortOrder || left.name.localeCompare(right.name))
      .map((type) => {
        const balance = balanceById.get(type.id)!;
        return {
          leaveTypeId: type.id,
          name: type.name,
          code: type.code,
          paid: type.paid,
          allowHalfDay: type.allowHalfDay,
          quota: balance.quota,
          used: balance.used,
          pending: balance.pending,
          remaining: balance.remaining,
        };
      });
    return { year, label: yearDetails.label, startDate: yearDetails.startDate,
      endDate: yearDetails.endDate, today, types: visibleTypes };
  }

  async apply(
    caller: LeaveCaller,
    input: { leaveTypeId: string; fromDate: string; toDate: string; reason: string; session?: LeaveSession },
  ): Promise<LeaveDto> {
    this.requireRole(caller.role, 'employee');
    const dates = this.expandRequest(input.fromDate, input.toDate);
    const months = monthsTouched(input.fromDate, input.toDate);
    const session = input.session ?? 'full';

    const id = await this.store.runTransaction(async (transaction) => {
      const [currentEmployee, leaveType, settingsDocument, holidayRows, lockedMonths, requests] = await Promise.all([
        transaction.getEmployee(caller.uid),
        transaction.getLeaveType(input.leaveTypeId),
        transaction.getCompanySettings(),
        transaction.getHolidays(months),
        Promise.all(months.map((month) => transaction.getPayrollMonth(month))),
        transaction.getEmployeeLeaveRequests(caller.uid),
      ]);
      if (!currentEmployee || currentEmployee.role !== 'employee' || currentEmployee.status !== 'active') {
        throw new AppError(403, 'FORBIDDEN', 'An active employee account is required.');
      }
      if (!leaveType) throw new AppError(404, 'LEAVE_TYPE_NOT_FOUND', 'Leave type was not found.');
      if (leaveType.status !== 'active' || leaveType.id === 'legacy-paid') {
        throw new AppError(422, 'LEAVE_TYPE_INACTIVE', 'This leave type is not available for new requests.');
      }
      this.assertWithinEmploymentWindow(currentEmployee, input.fromDate, input.toDate);

      const holidays = holidayRows
        .filter((holiday) => holidayAppliesToBranch(holiday, currentEmployee.primaryBranchId ?? null))
        .map((holiday) => String(holiday.date));
      const settings = attendanceSettingsFromDocument(settingsDocument);
      const requestedDates = countRequestedDates({
        dates,
        doj: typeof currentEmployee.doj === 'string' ? currentEmployee.doj : null,
        dol: typeof currentEmployee.dol === 'string' ? currentEmployee.dol : null,
        holidayMap: new Set(holidays),
        weeklyOffDays: settings.weeklyOffDays,
      });
      const weight = dayWeight(session);
      if (session !== 'full') {
        if (input.fromDate !== input.toDate) {
          throw new AppError(422, 'HALF_DAY_SINGLE_DATE', 'A half-day request must cover exactly one date.');
        }
        if (!leaveType.allowHalfDay) {
          throw new AppError(422, 'HALF_DAY_NOT_ALLOWED', 'This leave type does not allow half-day requests.');
        }
        if (requestedDates.length === 0) {
          throw new AppError(422, 'NOT_A_WORKING_DAY', 'Half-day leave must be requested on a working day.');
        }
      } else if (requestedDates.length === 0) {
        throw new AppError(422, 'NO_WORKING_DAYS', 'This range has no working days (weekly offs and holidays are not counted).');
      }

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

      const yearSplits = splitByLeaveYear(requestedDates, weight, settings.leaveYearStartMonth);
      for (const split of yearSplits) {
        if (leaveType.annualQuotaDays === null) continue;
        const balance = computeBalances({
          types: [leaveType],
          requests,
          yearStartDate: split.startDate,
          yearEndDate: split.endDate,
        })[0]!;
        if (wouldExceedQuota(leaveType.annualQuotaDays, balance.used, balance.pending, split.days)) {
          throw new AppError(422, 'QUOTA_EXCEEDED', `The ${leaveType.name} quota for ${split.yearLabel} would be exceeded.`, {
            leaveTypeId: leaveType.id,
            leaveTypeName: leaveType.name,
            yearLabel: split.yearLabel,
            quota: leaveType.annualQuotaDays,
            used: balance.used,
            pending: balance.pending,
            requested: split.days,
            remaining: leaveType.annualQuotaDays - balance.used - balance.pending,
          });
        }
      }

      const timestamp = this.store.serverTimestamp();
      return transaction.createLeaveRequest({
        empId: caller.uid,
        fromDate: dates[0]!,
        toDate: dates[dates.length - 1]!,
        reason: input.reason.trim(),
        status: 'pending',
        leaveTypeId: leaveType.id,
        leaveTypeName: leaveType.name,
        paid: leaveType.paid,
        session,
        requestedDates,
        requestedDays: requestedDates.length * weight,
        createdAt: timestamp,
        updatedAt: timestamp,
      });
    });
    return toLeaveRequestDto(await this.requirePersistedRequest(id));
  }

  async listMine(
    caller: LeaveCaller,
    status?: LeaveStatus | 'all',
  ): Promise<LeaveDto[]> {
    await this.requireActiveEmployee(caller);
    const requests = await this.store.listLeaveRequests({
      empId: caller.uid,
      limit: MAX_LIST_READS,
    });
    return sortNewestFirst(requests.filter((request) => status === undefined || status === 'all' || request.status === status))
      .map(toLeaveRequestDto);
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
        ...toLeaveRequestDto(request),
        name: employee?.name ?? '',
        empCode: employee?.empCode ?? null,
        designation: employee?.designation ?? '',
      };
    });
  }

  async getById(caller: LeaveCaller, id: string): Promise<LeaveDto> {
    if (caller.role !== 'admin' && caller.role !== 'employee') {
      throw this.forbidden();
    }
    const request = await this.store.getLeaveRequest(id);
    if (!request || (caller.role === 'employee' && request.empId !== caller.uid)) {
      throw new AppError(404, 'LEAVE_NOT_FOUND', 'Leave request was not found.');
    }
    return toLeaveRequestDto(request);
  }

  async cancel(caller: LeaveCaller, id: string): Promise<LeaveDto> {
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
    return toLeaveRequestDto(await this.requirePersistedRequest(id));
  }

  async decide(input: {
    caller: LeaveCaller;
    id: string;
    decision: 'approved' | 'rejected';
    note?: string;
  }): Promise<LeaveDto & { noDaysWritten?: true }> {
    this.requireRole(input.caller.role, 'admin');
    const noDaysWritten = await this.store.runTransaction(async (transaction) => {
      const request = await transaction.getLeaveRequest(input.id);
      if (!request) throw new AppError(404, 'LEAVE_NOT_FOUND', 'Leave request was not found.');
      if (request.status !== 'pending') {
        throw new AppError(409, 'ALREADY_DECIDED', 'This leave request is no longer pending.');
      }

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

      if (typeof request.leaveTypeId !== 'string') {
        throw new AppError(409, 'LEAVE_TYPE_MISSING', 'This older request has no leave type. Reject it or ask the employee to cancel and reapply.');
      }
      const months = monthsTouched(request.fromDate, request.toDate);
      const range = this.expandRequest(request.fromDate, request.toDate);
      const ids = months.map((month) => attendanceId(month, request.empId));
      const [employee, settingsDocument, leaveType, holidayDates, attendanceDocuments, payrollMonths, priorRequests] = await Promise.all([
        transaction.getEmployee(request.empId),
        transaction.getCompanySettings(),
        transaction.getLeaveType(request.leaveTypeId),
        transaction.getHolidays(months),
        Promise.all(ids.map((id) => transaction.getAttendance(id))),
        Promise.all(months.map((month) => transaction.getPayrollMonth(month))),
        transaction.getEmployeeLeaveRequests(request.empId),
      ]);
      if (!employee || employee.role !== 'employee') {
        throw new AppError(404, 'EMPLOYEE_NOT_FOUND', 'Employee was not found.');
      }
      if (!leaveType) throw new AppError(404, 'LEAVE_TYPE_NOT_FOUND', 'Leave type was not found.');

      const lockedIndex = payrollMonths.findIndex((month) => month?.locked === true);
      if (lockedIndex >= 0) throw this.monthLocked(months[lockedIndex]!);
      const settings = attendanceSettingsFromDocument(settingsDocument);
      const days: Record<string, { status?: unknown; halfLeave?: unknown }> = {};
      attendanceDocuments.forEach((document) => {
        if (document) {
          for (const [date, day] of Object.entries(document.days)) {
            days[date] = { status: day.status, halfLeave: day.halfLeave };
          }
        }
      });
      const holidaySet = new Set(holidayDates
        .filter((holiday) => holidayAppliesToBranch(holiday, employee.primaryBranchId ?? null))
        .map((holiday) => String(holiday.date)));
      const isHalfDay = request.session === 'first_half' || request.session === 'second_half';
      const weight = dayWeight(isHalfDay ? request.session as 'first_half' | 'second_half' : 'full');
      let writtenDates: string[];
      let skippedDates: Array<{ date: string; reason: string }>;
      if (isHalfDay) {
        const date = range[0];
        const result = date === undefined
          ? { write: false as const, reason: 'already_on_leave' as const }
          : classifyHalfLeaveDate({
            date,
            doj: typeof employee.doj === 'string' ? employee.doj : null,
            dol: typeof employee.dol === 'string' ? employee.dol : null,
            holidayMap: holidaySet,
            weeklyOffDays: settings.weeklyOffDays,
            day: days[date],
          });
        writtenDates = result.write ? [date!] : [];
        skippedDates = result.write ? [] : [{ date: date ?? request.fromDate, reason: result.reason }];
      } else {
        const classification = classifyLeaveDates({
          dates: range,
          doj: typeof employee.doj === 'string' ? employee.doj : null,
          dol: typeof employee.dol === 'string' ? employee.dol : null,
          holidays: holidaySet,
          weeklyOffDays: settings.weeklyOffDays,
          days,
        });
        writtenDates = classification.toWrite;
        skippedDates = classification.skipped;
      }

      const yearSplits = splitByLeaveYear(writtenDates, weight, settings.leaveYearStartMonth);
      for (const split of yearSplits) {
        if (leaveType.annualQuotaDays === null) continue;
        const approved = priorRequests.filter((prior) => prior.status === 'approved');
        const balance = computeBalances({
          types: [leaveType], requests: approved,
          yearStartDate: split.startDate, yearEndDate: split.endDate,
        })[0]!;
        if (wouldExceedQuota(leaveType.annualQuotaDays, balance.used, 0, split.days)) {
          throw new AppError(422, 'QUOTA_EXCEEDED', `The ${leaveType.name} quota for ${split.yearLabel} would be exceeded.`, {
            leaveTypeId: leaveType.id,
            leaveTypeName: leaveType.name,
            yearLabel: split.yearLabel,
            quota: leaveType.annualQuotaDays,
            used: balance.used,
            pending: 0,
            requested: split.days,
            remaining: leaveType.annualQuotaDays - balance.used,
          });
        }
      }
      const timestamp = this.store.serverTimestamp();
      for (const date of writtenDates) {
        const month = date.slice(0, 7);
        if (isHalfDay) {
          transaction.mergeAttendanceDay({
            id: attendanceId(month, request.empId), empId: request.empId, month, date,
            fields: { halfLeave: {
              session: request.session,
              paid: leaveType.paid,
              leaveTypeId: leaveType.id,
              leaveRequestId: input.id,
            } },
          });
        } else {
          transaction.setAttendanceDay({
            id: attendanceId(month, request.empId), empId: request.empId, month, date,
            day: {
              status: leaveType.paid ? 'L' : 'UL',
              source: 'leave', leaveRequestId: input.id, leaveTypeId: leaveType.id,
              editedBy: input.caller.uid, editedAt: timestamp,
            },
          });
        }
      }
      const writtenDays = writtenDates.length * weight;
      transaction.updateLeaveRequest(input.id, {
        status: 'approved',
        paid: leaveType.paid,
        writtenDates,
        skippedDates,
        writtenDays,
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
        leaveTypeId: leaveType.id,
        session: request.session ?? 'full',
        writtenDays,
        writtenDates,
        skippedDates,
        by: input.caller.uid,
        at: timestamp,
      });
      return writtenDays === 0;
    });

    const request = toLeaveRequestDto(await this.requirePersistedRequest(input.id));
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

export function toLeaveRequestDto(request: LeaveRequestRecord): LeaveDto {
  const legacyType = request.leaveType === 'paid' ? 'Paid Leave'
    : request.leaveType === 'unpaid' ? 'Unpaid Leave' : null;
  const dto: LeaveDto = {
    id: request.id,
    empId: request.empId,
    fromDate: request.fromDate,
    toDate: request.toDate,
    reason: request.reason,
    status: request.status,
    createdAt: request.createdAt,
    updatedAt: request.updatedAt,
    leaveTypeId: typeof request.leaveTypeId === 'string' ? request.leaveTypeId : null,
    leaveTypeName: typeof request.leaveTypeName === 'string' ? request.leaveTypeName : legacyType,
    paid: typeof request.paid === 'boolean' ? request.paid
      : request.leaveType === 'paid' ? true : request.leaveType === 'unpaid' ? false : null,
    session: request.session ?? 'full',
    requestedDates: request.requestedDates ?? [],
    requestedDays: typeof request.requestedDays === 'number' ? request.requestedDays : 0,
  };
  if (request.status === 'approved' || request.status === 'rejected') {
    if (request.leaveType !== undefined) dto.leaveType = request.leaveType;
    if (request.decidedBy !== undefined) dto.decidedBy = request.decidedBy;
    if (request.decidedAt !== undefined) dto.decidedAt = request.decidedAt;
    dto.decisionNote = request.decisionNote ?? null;
  }
  if (request.status === 'approved') {
    dto.writtenDates = request.writtenDates ?? [];
    dto.skippedDates = request.skippedDates ?? [];
    dto.writtenDays = typeof request.writtenDays === 'number' ? request.writtenDays : 0;
  }
  return dto;
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
