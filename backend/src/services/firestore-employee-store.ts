import { FieldValue, type Firestore } from 'firebase-admin/firestore';
import type {
  EmployeeRecord,
  EmployeeStore,
  EmployeeTransaction,
  SalaryRevision,
} from './employee-service';

export class FirestoreEmployeeStore implements EmployeeStore {
  constructor(private readonly firestore: Firestore) {}

  serverTimestamp(): unknown {
    return FieldValue.serverTimestamp();
  }

  runTransaction<T>(work: (transaction: EmployeeTransaction) => Promise<T>): Promise<T> {
    return this.firestore.runTransaction(async (firestoreTransaction) => {
      const counterRef = this.firestore.collection('counters').doc('employees');
      const getCounter = async () => {
        const snapshot = await firestoreTransaction.get(counterRef);
        return Number(snapshot.data()?.count ?? 0);
      };

      return work({
        getCounter,
        getEmployee: async (uid) => {
          const snapshot = await firestoreTransaction.get(
            this.firestore.collection('employees').doc(uid),
          );
          return snapshot.exists ? (snapshot.data() as EmployeeRecord) : undefined;
        },
        getSalaryRevision: async (id) => {
          const snapshot = await firestoreTransaction.get(
            this.firestore.collection('salary_history').doc(id),
          );
          return snapshot.exists ? (snapshot.data() as SalaryRevision) : undefined;
        },
        setCounter: (count) => {
          firestoreTransaction.set(counterRef, { count });
        },
        createEmployee: (uid, employee) => {
          firestoreTransaction.create(
            this.firestore.collection('employees').doc(uid),
            employee,
          );
        },
        createSalaryRevision: (id, revision) => {
          firestoreTransaction.create(
            this.firestore.collection('salary_history').doc(id),
            revision,
          );
        },
      });
    });
  }

  async listEmployees(): Promise<EmployeeRecord[]> {
    const snapshot = await this.firestore
      .collection('employees')
      .where('role', '==', 'employee')
      .orderBy('empCode')
      .get();
    return snapshot.docs.map((document) => ({
      ...(document.data() as EmployeeRecord),
      uid: document.id,
    }));
  }

  async getEmployee(uid: string): Promise<EmployeeRecord | undefined> {
    const snapshot = await this.firestore.collection('employees').doc(uid).get();
    return snapshot.exists
      ? { ...(snapshot.data() as EmployeeRecord), uid: snapshot.id }
      : undefined;
  }

  async getSalaryHistory(uid: string): Promise<SalaryRevision[]> {
    const snapshot = await this.firestore
      .collection('salary_history')
      .where('empId', '==', uid)
      .get();
    return snapshot.docs.map((document) => document.data() as SalaryRevision);
  }

  async updateEmployee(uid: string, values: Record<string, unknown>): Promise<void> {
    await this.firestore.collection('employees').doc(uid).update(values);
  }

  async getSalaryRevision(id: string): Promise<SalaryRevision | undefined> {
    const snapshot = await this.firestore.collection('salary_history').doc(id).get();
    return snapshot.exists ? (snapshot.data() as SalaryRevision) : undefined;
  }
}
