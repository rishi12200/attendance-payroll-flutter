import { isValidDateString, monthOf } from './dates';

export type ExpandDateRangeResult =
  | { ok: true; dates: string[] }
  | {
      ok: false;
      reason: 'invalid_date' | 'from_after_to' | 'range_too_long';
    };

export type LeaveSkipReason =
  | 'weekly_off'
  | 'holiday'
  | 'has_punch'
  | 'outside_employment';

export interface LeaveClassification {
  toWrite: string[];
  skipped: Array<{ date: string; reason: LeaveSkipReason }>;
}

export function expandDateRange(from: string, to: string): ExpandDateRangeResult {
  if (!isValidDateString(from) || !isValidDateString(to)) {
    return { ok: false, reason: 'invalid_date' };
  }
  if (from > to) return { ok: false, reason: 'from_after_to' };

  const dates: string[] = [];
  const cursor = new Date(`${from}T00:00:00.000Z`);
  const end = new Date(`${to}T00:00:00.000Z`);
  while (cursor <= end) {
    dates.push(cursor.toISOString().slice(0, 10));
    if (dates.length > 31) return { ok: false, reason: 'range_too_long' };
    cursor.setUTCDate(cursor.getUTCDate() + 1);
  }
  return { ok: true, dates };
}

export function monthsTouched(from: string, to: string): string[] {
  if (!isValidDateString(from) || !isValidDateString(to) || from > to) {
    throw new RangeError('Leave month calculation requires an ordered valid date range.');
  }
  const months: string[] = [];
  let month = monthOf(from);
  const lastMonth = monthOf(to);
  while (month <= lastMonth) {
    months.push(month);
    const [year, number] = month.split('-').map(Number);
    month = number === 12
      ? `${year! + 1}-01`
      : `${year}-${String(number! + 1).padStart(2, '0')}`;
  }
  return months;
}

export function rangesOverlap(
  aFrom: string,
  aTo: string,
  bFrom: string,
  bTo: string,
): boolean {
  for (const date of [aFrom, aTo, bFrom, bTo]) {
    if (!isValidDateString(date)) {
      throw new RangeError('Leave overlap requires valid YYYY-MM-DD dates.');
    }
  }
  if (aFrom > aTo || bFrom > bTo) {
    throw new RangeError('Leave overlap requires ordered date ranges.');
  }
  return aFrom <= bTo && bFrom <= aTo;
}

export function classifyLeaveDates(input: {
  dates: string[];
  doj?: string | null;
  dol?: string | null;
  holidays: ReadonlySet<string>;
  weeklyOffDays: readonly number[];
  days: Record<string, { status?: unknown } | undefined>;
}): LeaveClassification {
  const weeklyOffDays = new Set(input.weeklyOffDays);
  const toWrite: string[] = [];
  const skipped: LeaveClassification['skipped'] = [];

  for (const date of input.dates) {
    if (!isValidDateString(date)) {
      throw new RangeError('Leave classification requires valid YYYY-MM-DD dates.');
    }
    let reason: LeaveSkipReason | undefined;
    if ((input.doj != null && date < input.doj) || (input.dol != null && date > input.dol)) {
      reason = 'outside_employment';
    } else if (input.days[date]?.status === 'P' || input.days[date]?.status === 'H') {
      reason = 'has_punch';
    } else if (input.holidays.has(date)) {
      reason = 'holiday';
    } else {
      const weekday = new Date(`${date}T00:00:00.000Z`).getUTCDay();
      if (weeklyOffDays.has(weekday)) reason = 'weekly_off';
    }

    if (reason === undefined) toWrite.push(date);
    else skipped.push({ date, reason });
  }
  return { toWrite, skipped };
}
