import {
  FieldValue,
  type Firestore,
} from 'firebase-admin/firestore';
import type {
  AttendanceDay,
  AttendanceDocument,
  AttendanceStore,
  AttendanceTransaction,
  CheckinRecord,
  PayrollMonthDocument,
} from './attendance-store';

export class FirestoreAttendanceStore implements AttendanceStore {
  constructor(private readonly firestore: Firestore) {}

  serverTimestamp(): unknown {
    return FieldValue.serverTimestamp();
  }

  async getAttendance(id: string): Promise<AttendanceDocument | undefined> {
    const snapshot = await this.firestore.collection('attendance').doc(id).get();
    if (!snapshot.exists) return undefined;
    const data = snapshot.data()!;
    return {
      empId: String(data.empId),
      month: String(data.month),
      days: (data.days ?? {}) as Record<string, AttendanceDay>,
    };
  }

  async getCompanySettings(): Promise<Record<string, unknown> | undefined> {
    const snapshot = await this.firestore
      .collection('settings')
      .doc('company')
      .get();
    return snapshot.exists ? snapshot.data() : undefined;
  }

  async recordCheckin(record: CheckinRecord): Promise<void> {
    await this.firestore.collection('checkins').add(record);
  }

  runTransaction<T>(
    work: (transaction: AttendanceTransaction) => Promise<T>,
  ): Promise<T> {
    return this.firestore.runTransaction(async (firestoreTransaction) => {
      const attendanceCollection = this.firestore.collection('attendance');
      const payrollMonths = this.firestore.collection('payroll_months');

      return work({
        getAttendance: async (id) => {
          const snapshot = await firestoreTransaction.get(
            attendanceCollection.doc(id),
          );
          if (!snapshot.exists) return undefined;
          const data = snapshot.data()!;
          return {
            empId: String(data.empId),
            month: String(data.month),
            days: (data.days ?? {}) as Record<string, AttendanceDay>,
          };
        },
        getPayrollMonth: async (month) => {
          const snapshot = await firestoreTransaction.get(
            payrollMonths.doc(month),
          );
          return snapshot.exists
            ? (snapshot.data() as PayrollMonthDocument)
            : undefined;
        },
        setAttendanceDay: ({ id, empId, month, date, day }) => {
          firestoreTransaction.set(
            attendanceCollection.doc(id),
            {
              empId,
              month,
              days: { [date]: day },
            },
            { merge: true },
          );
        },
        createCheckin: (record) => {
          firestoreTransaction.create(
            this.firestore.collection('checkins').doc(),
            record,
          );
        },
      });
    });
  }
}
