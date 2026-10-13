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
  listAllHolidays(): Promise<import('../domain/holidays').HolidayInput[]>;
  listHolidayBranches(): Promise<Array<{ id: string; state: string; status: string }>>;
  getEmployeeBranch(uid: string): Promise<string | null>;
  getHoliday(id: string): Promise<import('../domain/holidays').HolidayInput | undefined>;
  writeHoliday(input: { id?: string; values: Record<string, unknown>; audit: Record<string, unknown> }): Promise<string>;
  deleteHoliday(id: string, audit: Record<string, unknown>): Promise<boolean>;
  serverTimestamp(): unknown;
  listCheckinsByDate(fromDate: string, toDate: string): Promise<FlaggedCheckinRecord[]>;
  runAttendanceEdit<T>(
    work: (transaction: AttendanceEditTransaction) => Promise<T>,
  ): Promise<T>;
}
