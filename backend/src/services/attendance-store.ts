import type { EmployeeRecord } from './employee-service';
import type { AttendanceSettings } from '../domain/attendance';

export type PunchType = 'in' | 'out';

export interface AttendanceDay extends Record<string, unknown> {
  inTime?: unknown;
  outTime?: unknown;
}

export interface AttendanceDocument {
  empId: string;
  month: string;
  days: Record<string, AttendanceDay>;
}

export interface PayrollMonthDocument {
  locked?: boolean;
}

export interface CheckinRecord extends Record<string, unknown> {
  empId: string;
  type: PunchType;
  serverTime: unknown;
  date: string;
  lat: number;
  lng: number;
  accuracy: number;
  branchId: string | null;
  distance: number | null;
  deviceId: string;
  isMocked: boolean;
  accepted: boolean;
  rejectReason: string | null;
}

export interface AttendanceTransaction {
  getAttendance(id: string): Promise<AttendanceDocument | undefined>;
  getPayrollMonth(month: string): Promise<PayrollMonthDocument | undefined>;
  setAttendanceDay(input: {
    id: string;
    empId: string;
    month: string;
    date: string;
    day: AttendanceDay;
  }): void;
  createCheckin(record: CheckinRecord): void;
}

export interface AttendanceStore {
  serverTimestamp(): unknown;
  getAttendance(id: string): Promise<AttendanceDocument | undefined>;
  getCompanySettings(): Promise<Record<string, unknown> | undefined>;
  recordCheckin(record: CheckinRecord): Promise<void>;
  runTransaction<T>(
    work: (transaction: AttendanceTransaction) => Promise<T>,
  ): Promise<T>;
}

export interface AttendanceEmployeeStore {
  getEmployee(uid: string): Promise<EmployeeRecord | undefined>;
}

export interface AttendanceBranch {
  id: string;
  name: string;
  lat: number;
  lng: number;
  radiusMeters: number;
  status: string;
}

export interface AttendanceBranchStore {
  listBranches(): Promise<AttendanceBranch[]>;
}

export interface AttendanceCaller {
  uid: string;
  role: string;
}

export interface PunchInput {
  lat: number;
  lng: number;
  accuracy: number;
  deviceId: string;
  isMocked: boolean;
}

export interface AttendanceSettingsReader {
  (): Promise<AttendanceSettings>;
}
