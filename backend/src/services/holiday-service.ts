import { AppError } from '../errors/app-error';
import { monthOf } from '../domain/dates';

export interface HolidayRecord {
  date: string;
  name: string;
  [key: string]: unknown;
}

export interface HolidayStore {
  listHolidays(fromDate: string, toDate: string): Promise<HolidayRecord[]>;
  getHoliday(date: string): Promise<HolidayRecord | undefined>;
  createHoliday(holiday: HolidayRecord): Promise<void>;
  deleteHoliday(date: string): Promise<boolean>;
  getPayrollMonth(month: string): Promise<{ locked?: boolean } | undefined>;
}

export class HolidayService {
  constructor(private readonly store: HolidayStore) {}

  async listHolidays(
    caller: { role: string },
    year: string,
  ): Promise<HolidayRecord[]> {
    if (caller.role !== 'admin' && caller.role !== 'employee') {
      throw new AppError(403, 'FORBIDDEN', 'A signed-in account is required.');
    }
    return (await this.store.listHolidays(`${year}-01-01`, `${year}-12-31`))
      .sort((left, right) => left.date.localeCompare(right.date));
  }

  async createHoliday(
    caller: { role: string },
    input: { date: string; name: string },
  ): Promise<HolidayRecord> {
    this.requireAdmin(caller.role);
    await this.assertMonthUnlocked(input.date);
    if (await this.store.getHoliday(input.date)) {
      throw new AppError(409, 'HOLIDAY_EXISTS', 'A holiday already exists for this date.');
    }
    const holiday = { date: input.date, name: input.name };
    await this.store.createHoliday(holiday);
    return holiday;
  }

  async deleteHoliday(caller: { role: string }, date: string): Promise<void> {
    this.requireAdmin(caller.role);
    await this.assertMonthUnlocked(date);
    if (!(await this.store.deleteHoliday(date))) {
      throw new AppError(404, 'HOLIDAY_NOT_FOUND', 'Holiday was not found.');
    }
  }

  private async assertMonthUnlocked(date: string): Promise<void> {
    const month = monthOf(date);
    if ((await this.store.getPayrollMonth(month))?.locked === true) {
      throw new AppError(409, 'MONTH_LOCKED', `Attendance for ${month} is locked.`);
    }
  }

  private requireAdmin(role: string): void {
    if (role !== 'admin') {
      throw new AppError(403, 'FORBIDDEN', 'Only admins can manage holidays.');
    }
  }
}
