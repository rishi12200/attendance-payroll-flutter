const IST_OFFSET_MS = 5.5 * 60 * 60 * 1000;
const DATE_PATTERN = /^\d{4}-\d{2}-\d{2}$/;

export function istDateOf(date: Date): string {
  if (Number.isNaN(date.getTime())) {
    throw new RangeError('IST date requires a valid Date.');
  }
  return new Date(date.getTime() + IST_OFFSET_MS).toISOString().slice(0, 10);
}

export function monthOf(dateString: string): string {
  if (!isValidDateString(dateString)) {
    throw new RangeError('Month extraction requires a valid YYYY-MM-DD string.');
  }
  return dateString.slice(0, 7);
}

export function todayIST(now: Date = new Date()): string {
  return istDateOf(now);
}

export function isValidDateString(value: unknown): value is string {
  if (typeof value !== 'string' || !DATE_PATTERN.test(value)) return false;
  const date = new Date(`${value}T00:00:00.000Z`);
  return !Number.isNaN(date.getTime()) && date.toISOString().slice(0, 10) === value;
}

export function compareDateStrings(left: string, right: string): -1 | 0 | 1 {
  if (!isValidDateString(left) || !isValidDateString(right)) {
    throw new RangeError('Date comparisons require valid YYYY-MM-DD strings.');
  }
  if (left < right) return -1;
  if (left > right) return 1;
  return 0;
}

export function isDateOnOrBefore(left: string, right: string): boolean {
  return compareDateStrings(left, right) <= 0;
}

export function isDateBefore(left: string, right: string): boolean {
  return compareDateStrings(left, right) < 0;
}
