import { isValidDateString } from './dates';

export interface HolidayInput {
  id?: string;
  date?: string;
  name?: string;
  scope?: 'all' | 'branches';
  branchIds?: string[];
  createdBy?: string;
  createdAt?: unknown;
  [key: string]: unknown;
}

export function normalizeHoliday(id: string, value: HolidayInput): HolidayInput | undefined {
  const date = typeof value.date === 'string' ? value.date : id;
  if (!isValidDateString(date) || typeof value.name !== 'string' || !value.name.trim()) return undefined;
  const scope = value.scope === 'branches' ? 'branches' : 'all';
  return { ...value, id, date, name: value.name.trim(), scope,
    branchIds: scope === 'branches' && Array.isArray(value.branchIds) ? [...new Set(value.branchIds)] : [] };
}

export function holidayAppliesToBranch(holiday: HolidayInput, branchId: string | null | undefined): boolean {
  return holiday.scope !== 'branches' || (branchId != null && Array.isArray(holiday.branchIds) && holiday.branchIds.includes(branchId));
}

export function holidayNameMap(holidays: readonly HolidayInput[]): Record<string, string> {
  const grouped = new Map<string, Set<string>>();
  for (const holiday of holidays) {
    if (typeof holiday.date !== 'string' || typeof holiday.name !== 'string') continue;
    const names = grouped.get(holiday.date) ?? new Set<string>();
    names.add(holiday.name);
    grouped.set(holiday.date, names);
  }
  return Object.fromEntries([...grouped].map(([date, names]) => [date, [...names].sort((a, b) => a.localeCompare(b)).join(', ')]));
}

export function expandStateToBranchIds(state: string, branches: readonly { id: string; state: string; status: string }[]): string[] {
  const target = state.trim().toLocaleLowerCase();
  return branches.filter((branch) => branch.status === 'active' && branch.state.trim().toLocaleLowerCase() === target).map(({ id }) => id).sort();
}

export function holidayScopesOverlap(left: HolidayInput, right: HolidayInput): boolean {
  if (left.scope !== 'branches' || right.scope !== 'branches') return true;
  const a = new Set(left.branchIds ?? []);
  return (right.branchIds ?? []).some((id) => a.has(id));
}

/** Returns every same-date holiday whose branch scope intersects the candidate. */
export function findOverlappingHolidays(
  existing: readonly HolidayInput[],
  candidate: HolidayInput,
): HolidayInput[] {
  return existing.filter(
    (holiday) =>
      holiday.date === candidate.date &&
      holidayScopesOverlap(holiday, candidate),
  );
}
