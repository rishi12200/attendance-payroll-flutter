import { AppError } from '../errors/app-error';
import {
  attendanceSettingsFromDocument,
  workedMinutes,
} from '../domain/attendance';
import {
  evaluateGeofence,
  type NearestGeofenceBranch,
} from '../domain/branches';
import {
  compareDateStrings,
  istDateOf,
  monthOf,
} from '../domain/dates';
import type { EmployeeRecord } from './employee-service';
import type {
  AttendanceBranch,
  AttendanceBranchStore,
  AttendanceCaller,
  AttendanceDay,
  AttendanceEmployeeStore,
  AttendanceSettingsReader,
  AttendanceStore,
  CheckinRecord,
  PunchInput,
  PunchType,
} from './attendance-store';

const DAY_MS = 24 * 60 * 60 * 1000;

export interface AttendanceServiceDependencies {
  store: AttendanceStore;
  employees: AttendanceEmployeeStore;
  branches: AttendanceBranchStore;
  now?: () => Date;
  readSettings?: AttendanceSettingsReader;
  logRejectedWriteFailure?: () => void;
}

function attendanceId(month: string, uid: string): string {
  return `${month}_${uid}`;
}

function dateBefore(date: string): string {
  const previous = new Date(`${date}T00:00:00.000Z`);
  previous.setUTCDate(previous.getUTCDate() - 1);
  return previous.toISOString().slice(0, 10);
}

function timestampDate(value: unknown): Date | undefined {
  if (value instanceof Date) {
    return Number.isNaN(value.getTime()) ? undefined : value;
  }
  if (typeof value === 'string' || typeof value === 'number') {
    const date = new Date(value);
    return Number.isNaN(date.getTime()) ? undefined : date;
  }
  if (
    typeof value === 'object' &&
    value !== null &&
    'toDate' in value &&
    typeof value.toDate === 'function'
  ) {
    const date = value.toDate();
    return date instanceof Date && !Number.isNaN(date.getTime())
      ? date
      : undefined;
  }
  return undefined;
}

export class AttendanceService {
  private readonly store: AttendanceStore;
  private readonly employees: AttendanceEmployeeStore;
  private readonly branches: AttendanceBranchStore;
  private readonly now: () => Date;
  private readonly readSettings: AttendanceSettingsReader;
  private readonly logRejectedWriteFailure: () => void;

  constructor(dependencies: AttendanceServiceDependencies) {
    this.store = dependencies.store;
    this.employees = dependencies.employees;
    this.branches = dependencies.branches;
    this.now = dependencies.now ?? (() => new Date());
    this.readSettings =
      dependencies.readSettings ??
      (async () =>
        attendanceSettingsFromDocument(await this.store.getCompanySettings()));
    this.logRejectedWriteFailure =
      dependencies.logRejectedWriteFailure ??
      (() => console.error('Could not record rejected attendance attempt.'));
  }

  async checkIn(
    caller: AttendanceCaller,
    input: PunchInput,
  ): Promise<Record<string, unknown>> {
    this.requireEmployee(caller);
    const now = this.now();
    const date = istDateOf(now);
    const employee = await this.requireEligibleEmployee(caller.uid, date);
    const { settings, allowedBranches, nearest, inside } = await this.getLocationContext(
      employee,
      input,
    );

    if (allowedBranches.length === 0) {
      await this.rejectAttempt(caller.uid, 'in', date, input, 'NO_BRANCH_ASSIGNED', nearest);
      throw new AppError(
        422,
        'NO_BRANCH_ASSIGNED',
        'This employee has no active branch assigned.',
      );
    }
    if (input.accuracy > settings.maxAccuracyMeters) {
      await this.rejectAttempt(caller.uid, 'in', date, input, 'ACCURACY_TOO_LOW', nearest);
      throw new AppError(
        422,
        'ACCURACY_TOO_LOW',
        `Location accuracy must be ${settings.maxAccuracyMeters} metres or better.`,
        { accuracy: input.accuracy, maxAccuracyMeters: settings.maxAccuracyMeters },
      );
    }
    if (input.isMocked && settings.rejectMockLocation) {
      await this.rejectAttempt(caller.uid, 'in', date, input, 'MOCK_LOCATION', nearest);
      throw new AppError(422, 'MOCK_LOCATION', 'Mock locations are not accepted.');
    }
    if (!nearest || !inside) {
      await this.rejectAttempt(caller.uid, 'in', date, input, 'OUTSIDE_GEOFENCE', nearest);
      throw this.outsideGeofenceError(nearest, input.accuracy);
    }

    const month = monthOf(date);
    const dayId = attendanceId(month, caller.uid);
    const serverTime = this.store.serverTimestamp();
    await this.store.runTransaction(async (transaction) => {
      const payrollMonth = await transaction.getPayrollMonth(month);
      const attendance = await transaction.getAttendance(dayId);
      if (payrollMonth?.locked === true) {
        throw this.monthLocked(month);
      }
      if (attendance?.days[date]?.inTime !== undefined) {
        throw new AppError(409, 'ALREADY_CHECKED_IN', 'Already checked in for today.');
      }

      transaction.createCheckin(
        this.checkinRecord(caller.uid, 'in', date, input, nearest, true, null, serverTime),
      );
      transaction.setAttendanceDay({
        id: dayId,
        empId: caller.uid,
        month,
        date,
        day: {
          ...attendance?.days[date],
          status: 'P',
          inTime: serverTime,
          inBranchId: nearest.id,
          inDistance: nearest.distanceMeters,
          source: 'app',
        },
      });
    });

    const persisted = await this.requirePersistedDay(dayId, date);
    return {
      date,
      status: persisted.status,
      inTime: persisted.inTime,
      branchId: nearest.id,
      branchName: nearest.name,
      distanceMeters: nearest.distanceMeters,
    };
  }

  async checkOut(
    caller: AttendanceCaller,
    input: PunchInput,
  ): Promise<Record<string, unknown>> {
    this.requireEmployee(caller);
    const now = this.now();
    const today = istDateOf(now);
    const employee = await this.requireEligibleEmployee(caller.uid, today);
    const { settings, allowedBranches, nearest, inside } = await this.getLocationContext(
      employee,
      input,
    );

    if (allowedBranches.length === 0) {
      await this.rejectAttempt(caller.uid, 'out', today, input, 'NO_BRANCH_ASSIGNED', nearest);
      throw new AppError(
        422,
        'NO_BRANCH_ASSIGNED',
        'No active branch is assigned to this employee.',
      );
    }
    if (input.isMocked && settings.rejectMockLocation) {
      await this.rejectAttempt(caller.uid, 'out', today, input, 'MOCK_LOCATION', nearest);
      throw new AppError(422, 'MOCK_LOCATION', 'Mock locations are not accepted.');
    }
    if (settings.enforceCheckoutLocation && input.accuracy > settings.maxAccuracyMeters) {
      await this.rejectAttempt(caller.uid, 'out', today, input, 'ACCURACY_TOO_LOW', nearest);
      throw new AppError(
        422,
        'ACCURACY_TOO_LOW',
        `Location accuracy must be ${settings.maxAccuracyMeters} metres or better.`,
        { accuracy: input.accuracy, maxAccuracyMeters: settings.maxAccuracyMeters },
      );
    }
    if (
      settings.enforceCheckoutLocation &&
      (!nearest || !inside)
    ) {
      await this.rejectAttempt(caller.uid, 'out', today, input, 'OUTSIDE_GEOFENCE', nearest);
      throw this.outsideGeofenceError(nearest, input.accuracy);
    }

    const yesterday = dateBefore(today);
    const candidateDates = [today, yesterday];
    const months = [...new Set(candidateDates.map(monthOf))];
    const ids = [...new Set(months.map((month) => attendanceId(month, caller.uid)))];
    const serverTime = this.store.serverTimestamp();
    const selected = await this.store.runTransaction(async (transaction) => {
      const attendanceDocuments = new Map<string, Awaited<ReturnType<typeof transaction.getAttendance>>>();
      for (const id of ids) {
        attendanceDocuments.set(id, await transaction.getAttendance(id));
      }
      const payrollMonths = new Map<string, Awaited<ReturnType<typeof transaction.getPayrollMonth>>>();
      for (const month of months) {
        payrollMonths.set(month, await transaction.getPayrollMonth(month));
      }

      let selectedDate: string | undefined;
      let selectedDay: AttendanceDay | undefined;
      for (const date of candidateDates) {
        const day = attendanceDocuments.get(attendanceId(monthOf(date), caller.uid))?.days[date];
        if (day?.inTime === undefined || day.outTime !== undefined) continue;
        if (date === yesterday) {
          const inTime = timestampDate(day.inTime);
          const elapsed = inTime ? now.getTime() - inTime.getTime() : -1;
          if (elapsed < 0 || elapsed >= DAY_MS) continue;
        }
        selectedDate = date;
        selectedDay = day;
        break;
      }

      if (!selectedDate || !selectedDay) {
        const todayDay =
          attendanceDocuments.get(attendanceId(monthOf(today), caller.uid))?.days[today];
        const yesterdayDay =
          attendanceDocuments.get(attendanceId(monthOf(yesterday), caller.uid))?.days[yesterday];
        const closedDay = [todayDay, yesterdayDay].find((day) => {
          if (day?.inTime === undefined || day.outTime === undefined) return false;
          const inTime = timestampDate(day.inTime);
          const elapsed = inTime ? now.getTime() - inTime.getTime() : -1;
          return elapsed >= 0 && elapsed < DAY_MS;
        });
        if (closedDay) {
          throw new AppError(409, 'ALREADY_CHECKED_OUT', 'Already checked out for this check-in.');
        }
        throw new AppError(409, 'NOT_CHECKED_IN', 'No open check-in was found.');
      }

      const month = monthOf(selectedDate);
      if (payrollMonths.get(month)?.locked === true) {
        throw this.monthLocked(month);
      }
      const dayId = attendanceId(month, caller.uid);
      const inTime = timestampDate(selectedDay.inTime);
      if (!inTime) {
        throw new AppError(409, 'NOT_CHECKED_IN', 'The stored check-in time is invalid.');
      }
      const minutes = workedMinutes(inTime, now);
      transaction.createCheckin(
        this.checkinRecord(caller.uid, 'out', today, input, nearest, true, null, serverTime),
      );
      transaction.setAttendanceDay({
        id: dayId,
        empId: caller.uid,
        month,
        date: selectedDate,
        day: {
          ...selectedDay,
          outTime: serverTime,
          outBranchId: nearest!.id,
          outDistance: nearest!.distanceMeters,
          workedMinutes: minutes,
        },
      });
      return { date: selectedDate, inTime: selectedDay.inTime, workedMinutes: minutes };
    });

    const persisted = await this.requirePersistedDay(
      attendanceId(monthOf(selected.date), caller.uid),
      selected.date,
    );
    return {
      date: selected.date,
      inTime: selected.inTime,
      outTime: persisted.outTime,
      workedMinutes: persisted.workedMinutes,
      branchId: nearest!.id,
      branchName: nearest!.name,
      distanceMeters: nearest!.distanceMeters,
    };
  }

  async getMyAttendance(
    caller: AttendanceCaller,
    month: string,
  ): Promise<Record<string, unknown>> {
    this.requireEmployee(caller);
    const now = this.now();
    const today = istDateOf(now);
    const document = await this.store.getAttendance(attendanceId(month, caller.uid));
    return {
      month,
      today,
      serverTime: now,
      days: document?.days ?? {},
    };
  }

  private requireEmployee(caller: AttendanceCaller): void {
    if (caller.role !== 'employee') {
      throw new AppError(403, 'FORBIDDEN', 'Attendance is only available to employees.');
    }
  }

  private async requireEligibleEmployee(
    uid: string,
    today: string,
  ): Promise<EmployeeRecord> {
    const employee = await this.employees.getEmployee(uid);
    if (!employee) {
      throw new AppError(404, 'EMPLOYEE_NOT_FOUND', 'Employee was not found.');
    }
    if (employee.role !== 'employee' || employee.status !== 'active') {
      throw new AppError(403, 'FORBIDDEN', 'Inactive employees cannot record attendance.');
    }
    if (typeof employee.doj === 'string' && compareDateStrings(employee.doj, today) > 0) {
      throw new AppError(422, 'NOT_YET_JOINED', 'Attendance is not allowed before the date of joining.');
    }
    if (typeof employee.dol === 'string' && compareDateStrings(employee.dol, today) < 0) {
      throw new AppError(422, 'EMPLOYMENT_ENDED', 'Attendance is not allowed after the date of leaving.');
    }
    return employee;
  }

  private async getLocationContext(
    employee: EmployeeRecord,
    input: PunchInput,
  ): Promise<{
    settings: Awaited<ReturnType<AttendanceSettingsReader>>;
    allowedBranches: AttendanceBranch[];
    nearest: NearestGeofenceBranch | null;
    inside: boolean;
  }> {
    const [settings, branches] = await Promise.all([
      this.readSettings(),
      this.branches.listBranches(),
    ]);
    const allowedIds = new Set(
      Array.isArray(employee.allowedBranchIds) ? employee.allowedBranchIds : [],
    );
    const allowedBranches = branches.filter(
      (branch) => branch.status === 'active' && allowedIds.has(branch.id),
    );
    const evaluation = evaluateGeofence({
      lat: input.lat,
      lng: input.lng,
      accuracy: input.accuracy,
      branches: allowedBranches,
    });
    return {
      settings,
      allowedBranches,
      nearest: evaluation.nearestBranch,
      inside: evaluation.inside,
    };
  }

  private async rejectAttempt(
    uid: string,
    type: PunchType,
    date: string,
    input: PunchInput,
    reason: string,
    nearest: NearestGeofenceBranch | null,
  ): Promise<void> {
    try {
      await this.store.recordCheckin(
        this.checkinRecord(
          uid,
          type,
          date,
          input,
          nearest,
          false,
          reason,
          this.store.serverTimestamp(),
        ),
      );
    } catch {
      this.logRejectedWriteFailure();
    }
  }

  private checkinRecord(
    empId: string,
    type: PunchType,
    date: string,
    input: PunchInput,
    nearest: NearestGeofenceBranch | null,
    accepted: boolean,
    rejectReason: string | null,
    serverTime: unknown,
  ): CheckinRecord {
    return {
      empId,
      type,
      serverTime,
      date,
      lat: input.lat,
      lng: input.lng,
      accuracy: input.accuracy,
      branchId: nearest?.id ?? null,
      distance: nearest?.distanceMeters ?? null,
      deviceId: input.deviceId,
      isMocked: input.isMocked,
      accepted,
      rejectReason,
    };
  }

  private outsideGeofenceError(
    nearest: NearestGeofenceBranch | null,
    accuracy: number,
  ): AppError {
    return new AppError(
      422,
      'OUTSIDE_GEOFENCE',
      'You are outside the allowed branch geofence.',
      {
        nearestBranchId: nearest?.id ?? null,
        nearestBranchName: nearest?.name ?? null,
        distanceMeters: nearest?.distanceMeters ?? null,
        radiusMeters: nearest?.radiusMeters ?? null,
        accuracy,
      },
    );
  }

  private monthLocked(month: string): AppError {
    return new AppError(409, 'MONTH_LOCKED', `Attendance for ${month} is locked.`);
  }

  private async requirePersistedDay(id: string, date: string): Promise<AttendanceDay> {
    const document = await this.store.getAttendance(id);
    const day = document?.days[date];
    if (!day) throw new Error('Attendance write completed but the day could not be re-read.');
    return day;
  }
}
