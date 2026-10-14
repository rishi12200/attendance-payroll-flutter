import {
  FieldPath,
  FieldValue,
  type Firestore,
} from 'firebase-admin/firestore';
import type { AttendanceDay, AttendanceDocument } from './attendance-store';
import type { EmployeeRecord } from './employee-service';
import { normalizeHoliday, type HolidayInput } from '../domain/holidays';
import type {
  LeaveAuditRecord,
  LeaveMonthLock,
  LeaveRequestRecord,
  LeaveStore,
  LeaveTransaction,
} from './leave-store';
import type { LeaveTypeRecord } from './leave-type-service';

const MAX_LIST_READS = 500;

export class FirestoreLeaveStore implements LeaveStore {
  constructor(private readonly firestore: Firestore) {}

  serverTimestamp(): unknown {
    return FieldValue.serverTimestamp();
  }

  async getLeaveRequest(id: string): Promise<LeaveRequestRecord | undefined> {
    const snapshot = await this.firestore.collection('leave_requests').doc(id).get();
    return snapshot.exists
      ? ({ ...snapshot.data(), id: snapshot.id } as LeaveRequestRecord)
      : undefined;
  }

  async listLeaveRequests(input: {
    empId?: string;
    limit: number;
  }): Promise<LeaveRequestRecord[]> {
    const cap = Math.min(MAX_LIST_READS, Math.max(0, Math.floor(input.limit)));
    const collection = this.firestore.collection('leave_requests');
    const snapshot = input.empId === undefined
      ? await collection.limit(cap).get()
      : await collection.where('empId', '==', input.empId).limit(cap).get();
    return snapshot.docs.map((document) => ({
      ...document.data(),
      id: document.id,
    }) as LeaveRequestRecord);
  }

  async getEmployee(uid: string): Promise<EmployeeRecord | undefined> {
    const snapshot = await this.firestore.collection('employees').doc(uid).get();
    return snapshot.exists
      ? ({ ...snapshot.data(), uid: snapshot.id } as EmployeeRecord)
      : undefined;
  }

  async getCompanySettings(): Promise<Record<string, unknown> | undefined> {
    const snapshot = await this.firestore.collection('settings').doc('company').get();
    return snapshot.exists ? snapshot.data() : undefined;
  }

  async listLeaveTypes() {
    const snapshot = await this.firestore.collection('leave_types').limit(100).get();
    return snapshot.docs.map((document) => ({ ...document.data(), id: document.id }) as import('./leave-type-service').LeaveTypeRecord);
  }

  runTransaction<T>(work: (transaction: LeaveTransaction) => Promise<T>): Promise<T> {
    return this.firestore.runTransaction(async (firestoreTransaction) => {
      const leaves = this.firestore.collection('leave_requests');
      const employees = this.firestore.collection('employees');
      const settings = this.firestore.collection('settings').doc('company');
      const leaveTypes = this.firestore.collection('leave_types');
      const attendance = this.firestore.collection('attendance');
      const payrollMonths = this.firestore.collection('payroll_months');
      const holidays = this.firestore.collection('holidays');
      const auditLogs = this.firestore.collection('audit_logs');
      const existingAttendance = new Set<string>();

      return work({
        getLeaveRequest: async (id) => {
          const snapshot = await firestoreTransaction.get(leaves.doc(id));
          return snapshot.exists
            ? ({ ...snapshot.data(), id: snapshot.id } as LeaveRequestRecord)
            : undefined;
        },
        getEmployee: async (uid) => {
          const snapshot = await firestoreTransaction.get(employees.doc(uid));
          return snapshot.exists
            ? ({ ...snapshot.data(), uid: snapshot.id } as EmployeeRecord)
            : undefined;
        },
        getCompanySettings: async () => {
          const snapshot = await firestoreTransaction.get(settings);
          return snapshot.exists ? snapshot.data() : undefined;
        },
        getLeaveType: async (id) => {
          const snapshot = await firestoreTransaction.get(leaveTypes.doc(id));
          return snapshot.exists
            ? { ...snapshot.data(), id: snapshot.id } as LeaveTypeRecord
            : undefined;
        },
        getHolidays: async (months) => {
          // Generated and legacy IDs coexist, so filter a bounded collection read in memory.
          const snapshot = await firestoreTransaction.get(holidays.limit(1000));
          return snapshot.docs.flatMap((document) => {
            const value = normalizeHoliday(document.id, document.data() as HolidayInput);
            if (!value) { console.warn(`Ignoring invalid holiday document ${document.id}`); return []; }
            return months.some((month) => String(value.date).startsWith(`${month}-`)) ? [value] : [];
          });
        },
        getAttendance: async (id) => {
          const snapshot = await firestoreTransaction.get(attendance.doc(id));
          if (!snapshot.exists) return undefined;
          const data = snapshot.data()!;
          existingAttendance.add(id);
          return {
            empId: String(data.empId ?? id.slice(id.indexOf('_') + 1)),
            month: String(data.month ?? id.slice(0, id.indexOf('_'))),
            days: (data.days ?? {}) as Record<string, AttendanceDay>,
          } satisfies AttendanceDocument;
        },
        getPayrollMonth: async (month) => {
          const snapshot = await firestoreTransaction.get(payrollMonths.doc(month));
          return snapshot.exists ? (snapshot.data() as LeaveMonthLock) : undefined;
        },
        getEmployeeLeaveRequests: async (empId) => {
          const snapshot = await firestoreTransaction.get(
            leaves.where('empId', '==', empId),
          );
          return snapshot.docs.map((document) => ({
            ...document.data(),
            id: document.id,
          }) as LeaveRequestRecord);
        },
        createLeaveRequest: (record) => {
          const reference = leaves.doc();
          firestoreTransaction.create(reference, record);
          return reference.id;
        },
        updateLeaveRequest: (id, changes) => {
          firestoreTransaction.update(leaves.doc(id), changes);
        },
        mergeAttendanceDay: ({ id, empId, month, date, fields }) => {
          const reference = attendance.doc(id);
          if (existingAttendance.has(id)) {
            for (const [field, value] of Object.entries(fields)) {
              firestoreTransaction.update(reference, new FieldPath('days', date, field), value);
            }
          } else {
            firestoreTransaction.set(
              reference,
              { empId, month, days: { [date]: fields } },
              { merge: true },
            );
          }
        },
        createAudit: (audit: LeaveAuditRecord) => {
          firestoreTransaction.create(auditLogs.doc(), audit);
        },
      });
    });
  }
}
