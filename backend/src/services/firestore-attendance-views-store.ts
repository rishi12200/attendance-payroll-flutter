import {
  FieldPath,
  FieldValue,
  type Firestore,
} from 'firebase-admin/firestore';
import type {
  AttendanceDay,
  AttendanceDocument,
  PayrollMonthDocument,
} from './attendance-store';
import type { HolidayRecord } from './holiday-service';
import type { LeaveTypeRecord } from './leave-type-service';
import { normalizeHoliday, type HolidayInput } from '../domain/holidays';
import type {
  AttendanceEditAudit,
  AttendanceEditTransaction,
  AttendanceViewsStore,
  FlaggedCheckinRecord,
} from './attendance-views-store';

export class FirestoreAttendanceViewsStore implements AttendanceViewsStore {
  constructor(private readonly firestore: Firestore) {}

  serverTimestamp(): unknown {
    return FieldValue.serverTimestamp();
  }

  async getCompanySettings(): Promise<Record<string, unknown> | undefined> {
    const snapshot = await this.firestore.collection('settings').doc('company').get();
    return snapshot.exists ? snapshot.data() : undefined;
  }

  async mergeCompanySettings(values: Record<string, unknown>): Promise<void> {
    await this.firestore
      .collection('settings')
      .doc('company')
      .set(values, { merge: true });
  }

  async getAttendance(id: string): Promise<AttendanceDocument | undefined> {
    const snapshot = await this.firestore.collection('attendance').doc(id).get();
    return snapshot.exists ? this.toAttendance(snapshot.id, snapshot.data()!) : undefined;
  }

  async getAttendanceDocuments(
    ids: string[],
  ): Promise<Map<string, AttendanceDocument>> {
    if (ids.length === 0) return new Map();
    const references = ids.map((id) => this.firestore.collection('attendance').doc(id));
    const snapshots = await this.firestore.getAll(...references);
    const documents = new Map<string, AttendanceDocument>();
    for (const snapshot of snapshots) {
      if (snapshot.exists) {
        documents.set(snapshot.id, this.toAttendance(snapshot.id, snapshot.data()!));
      }
    }
    return documents;
  }

  async getPayrollMonth(month: string): Promise<PayrollMonthDocument | undefined> {
    const snapshot = await this.firestore.collection('payroll_months').doc(month).get();
    return snapshot.exists ? (snapshot.data() as PayrollMonthDocument) : undefined;
  }

  async listHolidays(fromDate: string, toDate: string): Promise<HolidayRecord[]> {
    return (await this.listAllHolidays()).filter((holiday) => String(holiday.date) >= fromDate && String(holiday.date) <= toDate) as HolidayRecord[];
  }

  async listLeaveTypes(): Promise<LeaveTypeRecord[]> {
    const snapshot = await this.firestore.collection('leave_types').limit(100).get();
    return snapshot.docs.map((document) => ({ ...document.data(), id: document.id }) as LeaveTypeRecord);
  }

  async listAllHolidays(): Promise<HolidayInput[]> {
    // Generated IDs and legacy date IDs cannot both be selected by document-ID range.
    const snapshot = await this.firestore.collection('holidays').limit(1000).get();
    return snapshot.docs.flatMap((document) => {
      const raw = document.data() as HolidayInput;
      const value = normalizeHoliday(document.id, raw);
      if (!value) { console.warn(`Ignoring invalid holiday document ${document.id}`); return []; }
      return [value];
    });
  }

  async listHolidayBranches(): Promise<Array<{ id: string; state: string; status: string }>> {
    const snapshot = await this.firestore.collection('branches').get();
    return snapshot.docs.map((document) => ({ id: document.id, state: String(document.get('state') ?? ''), status: String(document.get('status') ?? '') }));
  }

  async getEmployeeBranch(uid: string): Promise<string | null> {
    const snapshot = await this.firestore.collection('employees').doc(uid).get();
    const branchId = snapshot.get('primaryBranchId');
    return typeof branchId === 'string' ? branchId : null;
  }

  async writeHoliday(input: { id?: string; values: Record<string, unknown>; audit: Record<string, unknown> }): Promise<string> {
    const reference = input.id ? this.firestore.collection('holidays').doc(input.id) : this.firestore.collection('holidays').doc();
    const batch = this.firestore.batch();
    batch.create(reference, input.values);
    batch.create(this.firestore.collection('audit_logs').doc(), input.audit);
    await batch.commit();
    return reference.id;
  }

  async getHoliday(id: string): Promise<HolidayRecord | undefined> {
    const snapshot = await this.firestore.collection('holidays').doc(id).get();
    if (!snapshot.exists) return undefined;
    const raw = snapshot.data() as HolidayInput;
    const normalized = normalizeHoliday(snapshot.id, raw);
    return normalized ? normalized as HolidayRecord : undefined;
  }

  async deleteHoliday(id: string, audit: Record<string, unknown>): Promise<boolean> {
    const reference = this.firestore.collection('holidays').doc(id);
    const snapshot = await reference.get();
    if (!snapshot.exists) return false;
    const batch = this.firestore.batch();
    batch.delete(reference);
    batch.create(this.firestore.collection('audit_logs').doc(), audit);
    await batch.commit();
    return true;
  }

  async listCheckinsByDate(
    fromDate: string,
    toDate: string,
  ): Promise<FlaggedCheckinRecord[]> {
    const snapshot = await this.firestore
      .collection('checkins')
      .where('date', '>=', fromDate)
      .where('date', '<=', toDate)
      .orderBy('date', 'desc')
      .limit(500)
      .get();
    return snapshot.docs.map((document) => ({
      ...(document.data() as Record<string, unknown>),
      id: document.id,
    }));
  }

  runAttendanceEdit<T>(
    work: (transaction: AttendanceEditTransaction) => Promise<T>,
  ): Promise<T> {
    return this.firestore.runTransaction(async (firestoreTransaction) => {
      const attendance = this.firestore.collection('attendance');
      const payrollMonths = this.firestore.collection('payroll_months');
      const auditLogs = this.firestore.collection('audit_logs');
      const existingAttendanceIds = new Set<string>();
      return work({
        getAttendance: async (id) => {
          const snapshot = await firestoreTransaction.get(attendance.doc(id));
          if (!snapshot.exists) return undefined;
          existingAttendanceIds.add(id);
          return this.toAttendance(snapshot.id, snapshot.data()!);
        },
        getPayrollMonth: async (month) => {
          const snapshot = await firestoreTransaction.get(payrollMonths.doc(month));
          return snapshot.exists
            ? (snapshot.data() as PayrollMonthDocument)
            : undefined;
        },
        setAttendanceDay: ({ id, empId, month, date, day }) => {
          const reference = attendance.doc(id);
          if (existingAttendanceIds.has(id)) {
            firestoreTransaction.update(reference, new FieldPath('days', date), day);
          } else {
            firestoreTransaction.set(
              reference,
              { empId, month, days: { [date]: day } },
              { merge: true },
            );
          }
        },
        createAudit: (audit: AttendanceEditAudit) => {
          firestoreTransaction.create(auditLogs.doc(), audit);
        },
      });
    });
  }

  private toAttendance(
    id: string,
    data: Record<string, unknown>,
  ): AttendanceDocument {
    const separator = id.indexOf('_');
    return {
      empId: String(data.empId ?? id.slice(separator + 1)),
      month: String(data.month ?? id.slice(0, separator)),
      days: (data.days ?? {}) as Record<string, AttendanceDay>,
    };
  }
}
