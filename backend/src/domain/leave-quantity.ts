import { isValidDateString } from './dates';
import { leaveYearByYear, leaveYearOf } from './leave-year';

export type LeaveSession = 'full' | 'first_half' | 'second_half';

export function dayWeight(session: LeaveSession): 0.5 | 1 {
  if (session === 'full') return 1;
  if (session === 'first_half' || session === 'second_half') return 0.5;
  throw new RangeError('Leave session must be full, first_half, or second_half.');
}

export function countRequestedDates(input: {
  dates: readonly string[];
  doj?: string | null;
  dol?: string | null;
  holidayMap: Readonly<Record<string, unknown>> | ReadonlySet<string>;
  weeklyOffDays: readonly number[];
}): string[] {
  if (input.doj != null && !isValidDateString(input.doj)) {
    throw new RangeError('Date of joining must be a valid YYYY-MM-DD date.');
  }
  if (input.dol != null && !isValidDateString(input.dol)) {
    throw new RangeError('Date of leaving must be a valid YYYY-MM-DD date.');
  }
  if (input.weeklyOffDays.some((day) => !Number.isInteger(day) || day < 0 || day > 6)) {
    throw new RangeError('Weekly off days must be integers from 0 to 6.');
  }
  const weeklyOffDays = new Set(input.weeklyOffDays);
  return [...new Set(input.dates)].filter((date) => {
    if (!isValidDateString(date)) {
      throw new RangeError('Leave quantity requires valid YYYY-MM-DD dates.');
    }
    if (input.doj != null && date < input.doj) return false;
    if (input.dol != null && date > input.dol) return false;
    const isHoliday = input.holidayMap instanceof Set
      ? input.holidayMap.has(date)
      : Object.hasOwn(input.holidayMap, date);
    if (isHoliday) return false;
    const weekday = new Date(`${date}T00:00:00.000Z`).getUTCDay();
    return !weeklyOffDays.has(weekday);
  });
}

export interface LeaveYearSplit {
  yearLabel: string;
  startDate: string;
  endDate: string;
  days: number;
}

export function splitByLeaveYear(
  dates: readonly string[],
  weight: number,
  startMonth: number,
): LeaveYearSplit[] {
  const weightHalves = toHalfUnits(weight);
  const years = new Map<number, number>();
  for (const date of [...new Set(dates)].sort()) {
    const leaveYear = leaveYearOf(date, startMonth);
    years.set(leaveYear.year, (years.get(leaveYear.year) ?? 0) + weightHalves);
  }
  return [...years]
    .sort(([left], [right]) => left - right)
    .map(([year, daysHalves]) => {
      const details = leaveYearByYear(year, startMonth);
      return {
        yearLabel: details.label,
        startDate: details.startDate,
        endDate: details.endDate,
        days: daysHalves / 2,
      };
    });
}

export function wouldExceedQuota(
  quota: number | null,
  used: number,
  pending: number,
  requested: number,
): boolean {
  if (quota === null) return false;
  return toHalfUnits(used) + toHalfUnits(pending) + toHalfUnits(requested) > toHalfUnits(quota);
}

export interface LeaveBalanceType {
  id: string;
  name: string;
  annualQuotaDays: number | null;
  [key: string]: unknown;
}

export interface LeaveBalanceRequest {
  status: string;
  leaveTypeId?: string | null;
  leaveType?: string | null;
  session?: LeaveSession | null;
  writtenDates?: readonly string[];
  requestedDates?: readonly string[];
}

export interface LeaveTypeBalance {
  leaveTypeId: string;
  name: string;
  quota: number | null;
  used: number;
  pending: number;
  remaining: number | null;
}

export function computeBalances(input: {
  types: readonly LeaveBalanceType[];
  requests: readonly LeaveBalanceRequest[];
  yearStartDate: string;
  yearEndDate: string;
}): LeaveTypeBalance[] {
  if (!isValidDateString(input.yearStartDate) || !isValidDateString(input.yearEndDate) ||
      input.yearStartDate > input.yearEndDate) {
    throw new RangeError('Balance calculation requires an ordered leave-year range.');
  }
  const result = input.types.map((type) => {
    let usedHalves = 0;
    let pendingHalves = 0;
    for (const request of input.requests) {
      const typeId = request.leaveTypeId ?? legacyTypeId(request);
      if (typeId !== type.id) continue;
      const approved = request.status === 'approved';
      const pending = request.status === 'pending';
      if (!approved && !pending) continue;
      const requestDates = approved ? request.writtenDates : request.requestedDates;
      if (!requestDates) continue;
      const dates = requestDates.filter(
        (date) => date >= input.yearStartDate && date <= input.yearEndDate,
      );
      const isLegacy = request.leaveTypeId == null;
      const weight = isLegacy ? 2 : toHalfUnits(dayWeight(request.session ?? 'full'));
      const units = dates.length * weight;
      if (approved) usedHalves += units;
      else pendingHalves += units;
    }
    const used = usedHalves / 2;
    const pending = pendingHalves / 2;
    return {
      leaveTypeId: type.id,
      name: type.name,
      quota: type.annualQuotaDays,
      used,
      pending,
      remaining: type.annualQuotaDays === null
        ? null
        : type.annualQuotaDays - used - pending,
    };
  });
  return result;
}

function legacyTypeId(request: LeaveBalanceRequest): string | undefined {
  if (request.status !== 'approved') return undefined;
  if (request.leaveType === 'paid') return 'legacy-paid';
  if (request.leaveType === 'unpaid') return 'unpaid';
  return undefined;
}

function toHalfUnits(days: number): number {
  if (!Number.isFinite(days) || days < 0 || !Number.isInteger(days * 2)) {
    throw new RangeError('Leave quantities must be non-negative multiples of 0.5.');
  }
  return days * 2;
}
