import type {
  AttendanceDocument,
  AttendanceDay,
  PayrollMonthDocument,
} from './attendance-store';
import type { HolidayRecord } from './holiday-service';

export interface AttendanceEditAudit {
  action: 'attendance.edit';
  empId: string;
  date: string;
  before: AttendanceDay | null;
  after: AttendanceDay;
  reason: string;
  by: string;
  at: unknown;
}

export interface AttendanceEditTransaction {
  getAttendance(id: string): Promise<AttendanceDocument | undefined>;
  getPayrollMonth(month: string): Promise<PayrollMonthDocument | undefined>;
  setAttendanceDay(input: {
    id: string;
    empId: string;
    month: string;
    date: string;
    day: AttendanceDay;
  }): void;
  createAudit(audit: AttendanceEditAudit): void;
}

export interface FlaggedCheckinRecord extends Record<string, unknown> {
  id: string;
}

export interface AttendanceViewsStore {
  serverTimestamp(): unknown;
  getCompanySettings(): Promise<Record<string, unknown> | undefined>;
  mergeCompanySettings(values: Record<string, unknown>): Promise<void>;
  getAttendance(id: string): Promise<AttendanceDocument | undefined>;
  getAttendanceDocuments(
    ids: string[],
  ): Promise<Map<string, AttendanceDocument>>;
  getPayrollMonth(month: string): Promise<PayrollMonthDocument | undefined>;
  listHolidays(fromDate: string, toDate: string): Promise<HolidayRecord[]>;
  getHoliday(date: string): Promise<HolidayRecord | undefined>;
  createHoliday(holiday: HolidayRecord): Promise<void>;
  deleteHoliday(date: string): Promise<boolean>;
  listCheckinsByDate(fromDate: string, toDate: string): Promise<FlaggedCheckinRecord[]>;
  runAttendanceEdit<T>(
    work: (transaction: AttendanceEditTransaction) => Promise<T>,
  ): Promise<T>;
}
