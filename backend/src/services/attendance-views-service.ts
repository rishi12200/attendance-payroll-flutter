import { AppError } from '../errors/app-error';
import {
  buildMonthCalendar,
  type CalendarSummary,
  type DayEntry,
  type StoredAttendanceDay,
} from '../domain/attendance-calendar';
import { attendanceSettingsFromDocument } from '../domain/attendance';
import {
  istDateOf,
  isValidDateString,
  monthOf,
} from '../domain/dates';
import type { AttendanceBranch } from './attendance-store';
import type { EmployeeRecord } from './employee-service';
import type { HolidayRecord } from './holiday-service';
import type {
  AttendanceEditAudit,
  AttendanceViewsStore,
  FlaggedCheckinRecord,
} from './attendance-views-store';

export interface AttendanceViewsEmployeeStore {
  getEmployee(uid: string): Promise<EmployeeRecord | undefined>;
  listEmployees(): Promise<EmployeeRecord[]>;
}

export interface AttendanceViewsBranchStore {
  listBranches(): Promise<AttendanceBranch[]>;
}

export interface AttendanceViewsServiceDependencies {
  store: AttendanceViewsStore;
  employees: AttendanceViewsEmployeeStore;
  branches: AttendanceViewsBranchStore;
  now?: () => Date;
}

export class AttendanceViewsService {
  private readonly now: () => Date;

  constructor(private readonly dependencies: AttendanceViewsServiceDependencies) {
    this.now = dependencies.now ?? (() => new Date());
  }

  async getMyCalendar(
    caller: { uid: string; role: string },
    month: string,
  ): Promise<Record<string, unknown>> {
    this.requireRole(caller.role, 'employee');
    const employee = await this.requireEmployee(caller.uid);
    return this.calendarResponse(employee, month);
  }

  async getEmployeeCalendar(
    caller: { role: string },
    uid: string,
    month: string,
  ): Promise<Record<string, unknown>> {
    this.requireRole(caller.role, 'admin');
    const employee = await this.requireEmployee(uid);
    return this.calendarResponse(employee, month);
  }

  async getSummary(
    caller: { uid: string; role: string },
    month: string,
    requestedEmpId?: string,
  ): Promise<Record<string, unknown> | Array<Record<string, unknown>>> {
    const { start, end } = monthRange(month);
    if (caller.role === 'employee') {
      if (requestedEmpId !== undefined && requestedEmpId !== caller.uid) {
        throw new AppError(
          403,
          'FORBIDDEN',
          'Employees may only read their own attendance summary.',
        );
      }
      const employee = await this.requireEmployee(caller.uid);
      const [{ summary }] = await this.calendarsForEmployees([employee], month);
      return {
        month,
        empId: caller.uid,
        empCode: employee.empCode ?? null,
        name: employee.name ?? '',
        summary,
      };
    }
    this.requireRole(caller.role, 'admin');

    if (requestedEmpId !== undefined) {
      const employee = await this.requireEmployee(requestedEmpId);
      const [{ summary }] = await this.calendarsForEmployees([employee], month);
      return {
        month,
        empId: requestedEmpId,
        empCode: employee.empCode ?? null,
        name: employee.name ?? '',
        summary,
      };
    }

    const employees = (await this.dependencies.employees.listEmployees())
      .filter(
        (employee) =>
          employee.role === 'employee' &&
          overlapsWindow(employee, start, end),
      )
      .sort((left, right) =>
        String(left.empCode ?? '').localeCompare(String(right.empCode ?? '')),
      );
    const calendars = await this.calendarsForEmployees(employees, month);
    return calendars.map(({ employee, summary }) => ({
      empId: employee.uid,
      empCode: employee.empCode ?? null,
      name: employee.name ?? '',
      summary,
    }));
  }

  async getByDate(
    caller: { role: string },
    date: string,
  ): Promise<Record<string, unknown>> {
    this.requireRole(caller.role, 'admin');
    const month = monthOf(date);
    const { start, end } = monthRange(month);
    const now = this.now();
    const today = istDateOf(now);
    const [employees, settingsDocument, holidays, branches] = await Promise.all([
      this.dependencies.employees.listEmployees(),
      this.dependencies.store.getCompanySettings(),
      this.dependencies.store.listHolidays(start, end),
      this.dependencies.branches.listBranches(),
    ]);
    const included = employees
      .filter(
        (employee) =>
          employee.role === 'employee' &&
          overlapsWindow(employee, date, date),
      )
      .sort((left, right) =>
        String(left.empCode ?? '').localeCompare(String(right.empCode ?? '')),
      );
    const attendance = await this.dependencies.store.getAttendanceDocuments(
      included.map((employee) => attendanceId(month, requireUid(employee))),
    );
    const holidayMap = holidayMapOf(holidays);
    const settings = attendanceSettingsFromDocument(settingsDocument);
    const branchNames = branchNameMap(branches);
    const rows: Record<string, unknown>[] = [];
    for (const employee of included) {
      const uid = requireUid(employee);
      const dayMap = attendance.get(attendanceId(month, uid))?.days ?? {};
      const { days } = buildMonthCalendar({
        month,
        today,
        doj: stringOrNull(employee.doj),
        dol: stringOrNull(employee.dol),
        days: dayMap,
        holidays: holidayMap,
        weeklyOffDays: settings.weeklyOffDays,
      });
      const entry = addBranchNames(
        days.find((day) => day.date === date)!,
        branchNames,
      );
      const hasOpenPunch = entry.inTime !== undefined && entry.outTime === undefined;
      rows.push({
        empId: uid,
        empCode: employee.empCode ?? null,
        name: employee.name ?? '',
        designation: employee.designation ?? '',
        ...entry,
        noCheckout: hasOpenPunch && date < today,
        checkedInNow: hasOpenPunch && date === today,
      });
    }
    const totals: Record<string, number> = {};
    for (const status of [
      'P',
      'H',
      'A',
      'L',
      'UL',
      'WEEKLY_OFF',
      'HOLIDAY',
      'PENDING',
    ]) {
      totals[status] = rows.filter((row) => row.status === status).length;
    }
    return { date, today, totals, rows };
  }

  async editAttendance(input: {
    caller: { uid: string; role: string };
    empId: string;
    date: string;
    status: 'P' | 'H' | 'A' | 'L' | 'UL';
    inTime?: string;
    outTime?: string;
    reason: string;
  }): Promise<DayEntry> {
    this.requireRole(input.caller.role, 'admin');
    const today = istDateOf(this.now());
    if (input.date > today) {
      throw new AppError(422, 'FUTURE_ATTENDANCE_DATE', 'Attendance cannot be edited for a future date.');
    }
    const employee = await this.requireEmployee(input.empId);
    if (!overlapsWindow(employee, input.date, input.date)) {
      throw new AppError(
        422,
        'OUTSIDE_EMPLOYMENT_WINDOW',
        'The date is outside the employee joining window.',
      );
    }
    const month = monthOf(input.date);
    const id = attendanceId(month, input.empId);
    const at = this.dependencies.store.serverTimestamp();
    await this.dependencies.store.runAttendanceEdit(async (transaction) => {
      const existing = await transaction.getAttendance(id);
      const payrollMonth = await transaction.getPayrollMonth(month);
      if (payrollMonth?.locked === true) {
        throw new AppError(409, 'MONTH_LOCKED', `Attendance for ${month} is locked.`);
      }
      const before = existing?.days[input.date] ?? null;
      const after = editedDay(before, input, input.date, input.caller.uid, at);
      transaction.setAttendanceDay({
        id,
        empId: input.empId,
        month,
        date: input.date,
        day: after,
      });
      const audit: AttendanceEditAudit = {
        action: 'attendance.edit',
        empId: input.empId,
        date: input.date,
        before,
        after,
        reason: input.reason,
        by: input.caller.uid,
        at,
      };
      transaction.createAudit(audit);
    });

    const { end } = monthRange(month);
    const [document, settingsDocument, holidays, branches] = await Promise.all([
      this.dependencies.store.getAttendance(id),
      this.dependencies.store.getCompanySettings(),
      this.dependencies.store.listHolidays(`${month}-01`, end),
      this.dependencies.branches.listBranches(),
    ]);
    const built = buildMonthCalendar({
      month,
      today,
      doj: stringOrNull(employee.doj),
      dol: stringOrNull(employee.dol),
      days: document?.days ?? {},
      holidays: holidayMapOf(holidays),
      weeklyOffDays: attendanceSettingsFromDocument(settingsDocument).weeklyOffDays,
    });
    return addBranchNames(
      built.days.find((day) => day.date === input.date)!,
      branchNameMap(branches),
    );
  }

  async getFlaggedCheckins(
    caller: { role: string },
    range: { from?: string; to?: string },
  ): Promise<Record<string, unknown>[]> {
    this.requireRole(caller.role, 'admin');
    const today = istDateOf(this.now());
    const to = range.to ?? today;
    const from = range.from ?? shiftDate(to, -6);
    if (!isValidDateString(from) || !isValidDateString(to) || from > to) {
      throw new AppError(400, 'INVALID_DATE_RANGE', 'A valid from/to date range is required.');
    }
    const inclusiveDays =
      (Date.parse(`${to}T00:00:00.000Z`) -
        Date.parse(`${from}T00:00:00.000Z`)) /
        86_400_000 +
      1;
    if (inclusiveDays > 31) {
      throw new AppError(400, 'INVALID_DATE_RANGE', 'The date range cannot exceed 31 days.');
    }
    const [records, employees, branches] = await Promise.all([
      this.dependencies.store.listCheckinsByDate(from, to),
      this.dependencies.employees.listEmployees(),
      this.dependencies.branches.listBranches(),
    ]);
    const employeeMap = new Map(
      employees.map((employee) => [requireUid(employee), employee]),
    );
    const branchNames = branchNameMap(branches);
    return records
      .filter((record) => record.accepted === false)
      .sort(compareCheckinsNewestFirst)
      .map((record) => {
        const empId = typeof record.empId === 'string' ? record.empId : '';
        const employee = employeeMap.get(empId);
        const branchId = typeof record.branchId === 'string' ? record.branchId : null;
        const nearestBranchName =
          typeof record.nearestBranchName === 'string'
            ? record.nearestBranchName
            : branchId === null
              ? null
              : branchNames.get(branchId) ?? branchId;
        return {
          id: record.id,
          empId,
          empCode: employee?.empCode ?? null,
          name: employee?.name ?? '',
          type: record.type,
          date: record.date,
          serverTime: record.serverTime,
          rejectReason: record.rejectReason ?? null,
          nearestBranchName,
          distanceMeters: record.distance ?? null,
          accuracy: record.accuracy ?? null,
          isMocked: record.isMocked ?? false,
          deviceId: record.deviceId ?? '',
        };
      });
  }

  private async calendarResponse(
    employee: EmployeeRecord,
    month: string,
  ): Promise<Record<string, unknown>> {
    const now = this.now();
    const today = istDateOf(now);
    const [{ days, summary }, branches] = await Promise.all([
      this.calendarsForEmployees([employee], month, now).then(([calendar]) => calendar),
      this.dependencies.branches.listBranches(),
    ]);
    const branchNames = branchNameMap(branches);
    return {
      month,
      today,
      serverTime: now,
      summary,
      days: days.map((day) => addBranchNames(day, branchNames)),
    };
  }

  private async calendarsForEmployees(
    employees: EmployeeRecord[],
    month: string,
    now = this.now(),
  ): Promise<Array<{ employee: EmployeeRecord; days: DayEntry[]; summary: CalendarSummary }>> {
    const { start, end } = monthRange(month);
    const today = istDateOf(now);
    const [settingsDocument, holidays, attendanceDocuments] = await Promise.all([
      this.dependencies.store.getCompanySettings(),
      this.dependencies.store.listHolidays(start, end),
      this.dependencies.store.getAttendanceDocuments(
        employees.map((employee) => attendanceId(month, requireUid(employee))),
      ),
    ]);
    const settings = attendanceSettingsFromDocument(settingsDocument);
    const holidayMap = holidayMapOf(holidays);
    return employees.map((employee) => {
      const id = requireUid(employee);
      const calendar = buildMonthCalendar({
        month,
        today,
        doj: stringOrNull(employee.doj),
        dol: stringOrNull(employee.dol),
        days: attendanceDocuments.get(attendanceId(month, id))?.days ?? {},
        holidays: holidayMap,
        weeklyOffDays: settings.weeklyOffDays,
      });
      return { employee, ...calendar };
    });
  }

  private async requireEmployee(uid: string): Promise<EmployeeRecord> {
    const employee = await this.dependencies.employees.getEmployee(uid);
    if (!employee || employee.role !== 'employee') {
      throw new AppError(404, 'EMPLOYEE_NOT_FOUND', 'Employee was not found.');
    }
    return employee;
  }

  private requireRole(actual: string, expected: 'admin' | 'employee'): void {
    if (actual !== expected) {
      throw new AppError(403, 'FORBIDDEN', `This attendance operation requires ${expected} role.`);
    }
  }
}

function editedDay(
  before: StoredAttendanceDay | null,
  input: {
    status: 'P' | 'H' | 'A' | 'L' | 'UL';
    inTime?: string;
    outTime?: string;
  },
  date: string,
  editedBy: string,
  at: unknown,
): Record<string, unknown> {
  const result: Record<string, unknown> = {
    ...(before ?? {}),
    status: input.status,
    source: 'admin_edit',
    editedBy,
    editedAt: at,
  };
  if (input.status === 'A' || input.status === 'L' || input.status === 'UL') {
    for (const field of [
      'inTime',
      'outTime',
      'inBranchId',
      'outBranchId',
      'inDistance',
      'outDistance',
      'workedMinutes',
    ]) {
      delete result[field];
    }
    return result;
  }

  const existingInTime = parseStoredDate(before?.inTime);
  const existingOutTime = parseStoredDate(before?.outTime);
  const inTime = input.inTime === undefined ? existingInTime : new Date(input.inTime);
  const outTime = input.outTime === undefined ? existingOutTime : new Date(input.outTime);
  if (inTime !== undefined && istDateOf(inTime) !== date) {
    throw new AppError(
      422,
      'INVALID_ATTENDANCE_TIMES',
      'In time must fall on the attendance date in IST.',
    );
  }
  if (input.outTime !== undefined && inTime === undefined) {
    throw new AppError(422, 'OUT_TIME_WITHOUT_IN_TIME', 'An out time requires an in time.');
  }
  if (inTime !== undefined) result.inTime = inTime;
  if (outTime !== undefined) result.outTime = outTime;
  if (inTime && outTime) {
    const elapsed = outTime.getTime() - inTime.getTime();
    if (elapsed <= 0 || elapsed > 86_400_000) {
      throw new AppError(
        422,
        'INVALID_ATTENDANCE_TIMES',
        'Out time must be after in time and no more than 24 hours later.',
      );
    }
    result.workedMinutes = Math.floor(elapsed / 60_000);
  } else {
    delete result.workedMinutes;
  }
  return result;
}

function parseStoredDate(value: unknown): Date | undefined {
  let date: Date | undefined;
  if (value instanceof Date) date = value;
  else if (typeof value === 'string' || typeof value === 'number') date = new Date(value);
  else if (
    typeof value === 'object' &&
    value !== null &&
    'toDate' in value &&
    typeof value.toDate === 'function'
  ) {
    date = value.toDate();
  }
  return date && Number.isFinite(date.getTime()) ? date : undefined;
}

function monthRange(month: string): { start: string; end: string } {
  const match = /^(\d{4})-(0[1-9]|1[0-2])$/.exec(month);
  if (!match) throw new AppError(400, 'VALIDATION_ERROR', 'Expected a YYYY-MM month.');
  const endDay = new Date(Date.UTC(Number(match[1]), Number(match[2]), 0))
    .getUTCDate();
  return { start: `${month}-01`, end: `${month}-${String(endDay).padStart(2, '0')}` };
}

function overlapsWindow(
  employee: EmployeeRecord,
  start: string,
  end: string,
): boolean {
  if (typeof employee.doj !== 'string' || !isValidDateString(employee.doj)) return false;
  if (employee.doj > end) return false;
  if (employee.dol == null) return true;
  return (
    typeof employee.dol === 'string' &&
    isValidDateString(employee.dol) &&
    employee.dol >= start
  );
}

function attendanceId(month: string, uid: string): string {
  return `${month}_${uid}`;
}

function requireUid(employee: EmployeeRecord): string {
  if (typeof employee.uid !== 'string' || employee.uid.length === 0) {
    throw new Error('Employee record is missing its uid.');
  }
  return employee.uid;
}

function stringOrNull(value: unknown): string | null {
  return typeof value === 'string' ? value : null;
}

function holidayMapOf(holidays: HolidayRecord[]): Record<string, string> {
  return Object.fromEntries(holidays.map(({ date, name }) => [date, name]));
}

function branchNameMap(branches: AttendanceBranch[]): Map<string, string> {
  return new Map(branches.map(({ id, name }) => [id, name]));
}

function addBranchNames(
  day: DayEntry,
  names: Map<string, string>,
): DayEntry & { inBranchName?: string; outBranchName?: string } {
  return {
    ...day,
    ...(typeof day.inBranchId === 'string'
      ? { inBranchName: names.get(day.inBranchId) ?? day.inBranchId }
      : {}),
    ...(typeof day.outBranchId === 'string'
      ? { outBranchName: names.get(day.outBranchId) ?? day.outBranchId }
      : {}),
  };
}

function shiftDate(date: string, days: number): string {
  const shifted = new Date(`${date}T00:00:00.000Z`);
  shifted.setUTCDate(shifted.getUTCDate() + days);
  return shifted.toISOString().slice(0, 10);
}

function compareCheckinsNewestFirst(
  left: FlaggedCheckinRecord,
  right: FlaggedCheckinRecord,
): number {
  const dateCompare = String(right.date ?? '').localeCompare(String(left.date ?? ''));
  if (dateCompare !== 0) return dateCompare;
  const time = (value: unknown) => parseStoredDate(value)?.getTime() ?? 0;
  return time(right.serverTime) - time(left.serverTime);
}
