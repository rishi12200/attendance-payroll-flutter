import { isValidDateString } from './dates';

export type CalendarStatus =
  | 'P'
  | 'H'
  | 'A'
  | 'L'
  | 'UL'
  | 'WEEKLY_OFF'
  | 'HOLIDAY'
  | 'NOT_JOINED'
  | 'LEFT'
  | 'PENDING';

export interface StoredAttendanceDay {
  status?: unknown;
  inTime?: unknown;
  outTime?: unknown;
  workedMinutes?: unknown;
  inBranchId?: unknown;
  outBranchId?: unknown;
  source?: unknown;
  editedBy?: unknown;
  editedAt?: unknown;
  [key: string]: unknown;
}

export interface DayEntry {
  date: string;
  weekday: number;
  status: CalendarStatus;
  derived: boolean;
  holidayName?: string;
  inTime?: unknown;
  outTime?: unknown;
  workedMinutes?: unknown;
  inBranchId?: unknown;
  outBranchId?: unknown;
  source?: unknown;
  editedBy?: unknown;
  editedAt?: unknown;
}

export interface CalendarSummary {
  daysInMonth: number;
  weeklyOffs: number;
  holidays: number;
  present: number;
  halfDays: number;
  absent: number;
  paidLeave: number;
  unpaidLeave: number;
  notJoinedOrLeftDays: number;
  pending: number;
  lop: number;
  payableDays: number;
}

export interface MonthCalendar {
  days: DayEntry[];
  summary: CalendarSummary;
}

const storedStatuses = new Set(['P', 'H', 'A', 'L', 'UL']);
const storedFields = [
  'inTime',
  'outTime',
  'workedMinutes',
  'inBranchId',
  'outBranchId',
  'source',
  'editedBy',
  'editedAt',
] as const;

export function buildMonthCalendar(input: {
  month: string;
  today: string;
  doj?: string | null;
  dol?: string | null;
  days: Record<string, StoredAttendanceDay>;
  holidays: Record<string, string>;
  weeklyOffDays: number[];
}): MonthCalendar {
  if (!/^\d{4}-(0[1-9]|1[0-2])$/.test(input.month)) {
    throw new RangeError('Calendar month must use YYYY-MM.');
  }
  if (!isValidDateString(input.today)) {
    throw new RangeError('Calendar today must be a valid YYYY-MM-DD date.');
  }
  if (input.doj != null && !isValidDateString(input.doj)) {
    throw new RangeError('Date of joining must be a valid YYYY-MM-DD date.');
  }
  if (input.dol != null && !isValidDateString(input.dol)) {
    throw new RangeError('Date of leaving must be a valid YYYY-MM-DD date.');
  }
  if (
    input.weeklyOffDays.some(
      (weekday) => !Number.isInteger(weekday) || weekday < 0 || weekday > 6,
    )
  ) {
    throw new RangeError('Weekly-off days must be weekday numbers from 0 to 6.');
  }

  const [year, month] = input.month.split('-').map(Number);
  const daysInMonth = new Date(Date.UTC(year!, month!, 0)).getUTCDate();
  const weeklyOffDays = new Set(input.weeklyOffDays);
  const days: DayEntry[] = [];

  for (let dayOfMonth = 1; dayOfMonth <= daysInMonth; dayOfMonth++) {
    const date = `${input.month}-${String(dayOfMonth).padStart(2, '0')}`;
    const weekday = new Date(`${date}T00:00:00.000Z`).getUTCDay();
    let record: StoredAttendanceDay | undefined = input.days[date];
    const beforeJoining = input.doj != null && date < input.doj;
    const afterLeaving = input.dol != null && date > input.dol;

    let status: CalendarStatus;
    let derived = false;
    let holidayName: string | undefined;
    if (beforeJoining) {
      status = 'NOT_JOINED';
      record = undefined;
    } else if (afterLeaving) {
      status = 'LEFT';
      record = undefined;
    } else if (record !== undefined) {
      if (typeof record.status !== 'string' || !storedStatuses.has(record.status)) {
        throw new TypeError(`Attendance record for ${date} has an invalid status.`);
      }
      status = record.status as CalendarStatus;
    } else if (Object.hasOwn(input.holidays, date)) {
      status = 'HOLIDAY';
      holidayName = input.holidays[date];
    } else if (weeklyOffDays.has(weekday)) {
      status = 'WEEKLY_OFF';
    } else if (date < input.today) {
      status = 'A';
      derived = true;
    } else {
      status = 'PENDING';
    }

    const entry: DayEntry = { date, weekday, status, derived };
    if (holidayName !== undefined) entry.holidayName = holidayName;
    if (record !== undefined) {
      for (const field of storedFields) {
        if (record[field] !== undefined) entry[field] = record[field];
      }
    }
    days.push(entry);
  }

  const count = (status: CalendarStatus) =>
    days.reduce((total, day) => total + Number(day.status === status), 0);
  const present = count('P');
  const halfDays = count('H');
  const absent = count('A');
  const paidLeave = count('L');
  const unpaidLeave = count('UL');
  const lop = absent + unpaidLeave + 0.5 * halfDays;
  const summary: CalendarSummary = {
    daysInMonth,
    weeklyOffs: count('WEEKLY_OFF'),
    holidays: count('HOLIDAY'),
    present,
    halfDays,
    absent,
    paidLeave,
    unpaidLeave,
    notJoinedOrLeftDays: count('NOT_JOINED') + count('LEFT'),
    pending: count('PENDING'),
    lop,
    payableDays: daysInMonth - lop,
  };
  return { days, summary };
}
