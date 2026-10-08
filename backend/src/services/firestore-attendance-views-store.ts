import {
  FieldPath,
  FieldValue,
  type Firestore,
} from 'firebase-admin/firestore';
import { AppError } from '../errors/app-error';
import type {
  AttendanceDay,
  AttendanceDocument,
  PayrollMonthDocument,
} from './attendance-store';
import type { HolidayRecord } from './holiday-service';
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
    const snapshot = await this.firestore
      .collection('holidays')
      .where(FieldPath.documentId(), '>=', fromDate)
      .where(FieldPath.documentId(), '<=', toDate)
      .orderBy(FieldPath.documentId())
      .get();
    return snapshot.docs.map((document) => ({
      ...(document.data() as HolidayRecord),
      date: document.id,
    }));
  }

  async getHoliday(date: string): Promise<HolidayRecord | undefined> {
    const snapshot = await this.firestore.collection('holidays').doc(date).get();
    return snapshot.exists
      ? { ...(snapshot.data() as HolidayRecord), date: snapshot.id }
      : undefined;
  }

  async createHoliday(holiday: HolidayRecord): Promise<void> {
    try {
      await this.firestore.collection('holidays').doc(holiday.date).create({
        name: holiday.name,
        date: holiday.date,
      });
    } catch (error) {
      if (firestoreCode(error) === 'already-exists' || firestoreCode(error) === '6') {
        throw new AppError(
          409,
          'HOLIDAY_EXISTS',
          'A holiday already exists for this date.',
        );
      }
      throw error;
    }
  }

  async deleteHoliday(date: string): Promise<boolean> {
    const reference = this.firestore.collection('holidays').doc(date);
    return this.firestore.runTransaction(async (transaction) => {
      const snapshot = await transaction.get(reference);
      if (!snapshot.exists) return false;
      transaction.delete(reference);
      return true;
    });
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

function firestoreCode(error: unknown): string | undefined {
  if (typeof error !== 'object' || error === null || !('code' in error)) {
    return undefined;
  }
  const code = error.code;
  return typeof code === 'string' || typeof code === 'number' ? String(code) : undefined;
}
