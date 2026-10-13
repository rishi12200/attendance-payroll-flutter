import { AppError } from '../errors/app-error';
import { monthOf } from '../domain/dates';
import { expandStateToBranchIds, holidayScopesOverlap, normalizeHoliday, type HolidayInput } from '../domain/holidays';

export interface HolidayRecord extends Record<string, unknown> {
  id: string; date: string; name: string; scope: 'all' | 'branches'; branchIds: string[];
}
export interface HolidayStore {
  listHolidays(fromDate: string, toDate: string): Promise<HolidayInput[]>;
  listAllHolidays(): Promise<HolidayInput[]>;
  getHoliday(id: string): Promise<HolidayInput | undefined>;
  listHolidayBranches(): Promise<Array<{ id: string; state: string; status: string }>>;
  getEmployeeBranch(uid: string): Promise<string | null>;
  writeHoliday(input: { id?: string; values: Record<string, unknown>; audit: Record<string, unknown> }): Promise<string>;
  deleteHoliday(id: string, audit: Record<string, unknown>): Promise<boolean>;
  getPayrollMonth(month: string): Promise<{ locked?: boolean } | undefined>;
  serverTimestamp(): unknown;
}

export interface HolidayDto extends HolidayRecord {}
export function toHolidayDto(id: string, value: HolidayInput): HolidayDto {
  const normalized = normalizeHoliday(id, value);
  if (!normalized) throw new AppError(500, 'INVALID_HOLIDAY_DATA', 'Stored holiday data is invalid.');
  return { id, date: normalized.date as string, name: normalized.name as string,
    scope: normalized.scope as 'all' | 'branches', branchIds: normalized.branchIds as string[],
    ...(normalized.createdBy !== undefined ? { createdBy: normalized.createdBy as string } : {}),
    ...(normalized.createdAt !== undefined ? { createdAt: normalized.createdAt } : {}) };
}

export class HolidayService {
  constructor(private readonly store: HolidayStore) {}
  async listHolidays(caller: { uid: string; role: string }, year: string, branchId?: string): Promise<HolidayDto[]> {
    if (caller.role !== 'admin' && caller.role !== 'employee') throw new AppError(403, 'FORBIDDEN', 'A signed-in account is required.');
    const values = (await this.store.listHolidays(`${year}-01-01`, `${year}-12-31`))
      .map((raw) => normalizeHoliday(String(raw.id ?? ''), raw)).filter((value): value is HolidayInput => value !== undefined);
    const effectiveBranch = caller.role === 'admin' ? branchId : (await this.store.getEmployeeBranch(caller.uid));
    return values.filter((value) => caller.role === 'admin' && branchId === undefined || value.scope !== 'branches' || (effectiveBranch != null && (value.branchIds as string[]).includes(effectiveBranch)))
      .map((value) => toHolidayDto(String(value.id), value)).sort((a, b) => a.date.localeCompare(b.date) || a.name.localeCompare(b.name));
  }
  async listMine(caller: { uid: string; role: string }, year: string): Promise<HolidayDto[]> {
    if (caller.role !== 'employee') throw new AppError(403, 'FORBIDDEN', 'Only employees can read their holidays.');
    return this.listHolidays(caller, year);
  }
  async createHoliday(caller: { uid: string; role: string }, input: { date: string; name: string; scope: 'all' | 'branches'; branchIds?: string[]; state?: string }): Promise<HolidayDto> {
    this.requireAdmin(caller.role);
    await this.assertMonthUnlocked(input.date);
    let branchIds = input.branchIds ?? [];
    if (input.state !== undefined) branchIds = expandStateToBranchIds(input.state, await this.store.listHolidayBranches());
    if (input.scope === 'branches') {
      const activeIds = new Set((await this.store.listHolidayBranches()).filter((b) => b.status === 'active').map((b) => b.id));
      if (!branchIds.length || branchIds.some((id) => !activeIds.has(id))) throw new AppError(400, 'INVALID_BRANCH_SCOPE', 'Branch-scoped holidays require active branch IDs.');
    } else branchIds = [];
    const values: HolidayInput = { date: input.date, name: input.name.trim(), scope: input.scope, branchIds };
    const existing = (await this.store.listHolidays(input.date, input.date)).map((raw) => normalizeHoliday(String(raw.id ?? ''), raw)).filter((item): item is HolidayInput => !!item);
    if (existing.some((item) => item.name === values.name && holidayScopesOverlap(item, values))) throw new AppError(409, 'HOLIDAY_EXISTS', 'An overlapping holiday with this name already exists for this date.');
    const timestamp = this.store.serverTimestamp();
    const id = await this.store.writeHoliday({ values: { date: input.date, name: input.name.trim(), scope: input.scope, branchIds, createdBy: caller.uid, createdAt: timestamp }, audit: { action: 'holiday.create', date: input.date, name: input.name.trim(), by: caller.uid, at: timestamp } });
    const stored = await this.store.getHoliday(id);
    return toHolidayDto(id, stored ?? { ...values, createdBy: caller.uid, createdAt: timestamp });
  }
  async deleteHoliday(caller: { uid: string; role: string }, id: string): Promise<void> {
    this.requireAdmin(caller.role);
    const raw = await this.store.getHoliday(id);
    if (!raw) throw new AppError(404, 'HOLIDAY_NOT_FOUND', 'Holiday was not found.');
    const normalized = normalizeHoliday(id, raw);
    if (!normalized) throw new AppError(500, 'INVALID_HOLIDAY_DATA', 'Stored holiday data is invalid.');
    await this.assertMonthUnlocked(normalized.date as string);
    const at = this.store.serverTimestamp();
    if (!(await this.store.deleteHoliday(id, { action: 'holiday.delete', holidayId: id, date: normalized.date, by: caller.uid, at }))) throw new AppError(404, 'HOLIDAY_NOT_FOUND', 'Holiday was not found.');
  }
  private async assertMonthUnlocked(date: string): Promise<void> {
    const month = monthOf(date);
    if ((await this.store.getPayrollMonth(month))?.locked === true) throw new AppError(409, 'MONTH_LOCKED', `Attendance for ${month} is locked.`);
  }
  private requireAdmin(role: string): void { if (role !== 'admin') throw new AppError(403, 'FORBIDDEN', 'Only admins can manage holidays.'); }
}
