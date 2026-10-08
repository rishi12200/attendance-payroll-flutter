import {
  FieldPath,
  FieldValue,
  type Firestore,
} from 'firebase-admin/firestore';
import type { AttendanceDay, AttendanceDocument } from './attendance-store';
import type { EmployeeRecord } from './employee-service';
import type {
  LeaveAuditRecord,
  LeaveMonthLock,
  LeaveRequestRecord,
  LeaveStore,
  LeaveTransaction,
} from './leave-store';

const MAX_LIST_READS = 200;

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

  runTransaction<T>(work: (transaction: LeaveTransaction) => Promise<T>): Promise<T> {
    return this.firestore.runTransaction(async (firestoreTransaction) => {
      const leaves = this.firestore.collection('leave_requests');
      const employees = this.firestore.collection('employees');
      const settings = this.firestore.collection('settings').doc('company');
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
        getHolidays: async (months) => {
          const snapshots = await Promise.all(months.map((month) => {
            const start = `${month}-01`;
            const [year, monthNumber] = month.split('-').map(Number);
            const endDate = new Date(Date.UTC(year!, monthNumber!, 0));
            const end = `${month}-${String(endDate.getUTCDate()).padStart(2, '0')}`;
            const query = holidays
              .where(FieldPath.documentId(), '>=', start)
              .where(FieldPath.documentId(), '<=', end);
            return firestoreTransaction.get(query);
          }));
          return snapshots.flatMap((snapshot) => snapshot.docs.map((document) => document.id));
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
        setAttendanceDay: ({ id, empId, month, date, day }) => {
          const reference = attendance.doc(id);
          if (existingAttendance.has(id)) {
            firestoreTransaction.update(reference, new FieldPath('days', date), day);
          } else {
            firestoreTransaction.set(
              reference,
              { empId, month, days: { [date]: day } },
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
