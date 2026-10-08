import type { AttendanceDay, AttendanceDocument } from './attendance-store';
import type { EmployeeRecord } from './employee-service';

export type LeaveStatus = 'pending' | 'approved' | 'rejected' | 'cancelled';
export type LeaveType = 'paid' | 'unpaid';

export interface LeaveRequestRecord extends Record<string, unknown> {
  id: string;
  empId: string;
  fromDate: string;
  toDate: string;
  reason: string;
  status: LeaveStatus;
}

export interface LeaveMonthLock {
  locked?: boolean;
}

export interface LeaveAuditRecord extends Record<string, unknown> {
  action: 'leave.decision';
  requestId: string;
  empId: string;
  decision: 'approved' | 'rejected';
  by: string;
  at: unknown;
}

export interface LeaveTransaction {
  getLeaveRequest(id: string): Promise<LeaveRequestRecord | undefined>;
  getEmployee(uid: string): Promise<EmployeeRecord | undefined>;
  getCompanySettings(): Promise<Record<string, unknown> | undefined>;
  getHolidays(months: string[]): Promise<string[]>;
  getAttendance(id: string): Promise<AttendanceDocument | undefined>;
  getPayrollMonth(month: string): Promise<LeaveMonthLock | undefined>;
  getEmployeeLeaveRequests(empId: string): Promise<LeaveRequestRecord[]>;
  createLeaveRequest(record: Omit<LeaveRequestRecord, 'id'>): string;
  updateLeaveRequest(id: string, changes: Record<string, unknown>): void;
  setAttendanceDay(input: {
    id: string;
    empId: string;
    month: string;
    date: string;
    day: AttendanceDay;
  }): void;
  createAudit(audit: LeaveAuditRecord): void;
}

export interface LeaveStore {
  serverTimestamp(): unknown;
  getLeaveRequest(id: string): Promise<LeaveRequestRecord | undefined>;
  listLeaveRequests(input: {
    empId?: string;
    limit: number;
  }): Promise<LeaveRequestRecord[]>;
  getEmployee(uid: string): Promise<EmployeeRecord | undefined>;
  runTransaction<T>(work: (transaction: LeaveTransaction) => Promise<T>): Promise<T>;
}
