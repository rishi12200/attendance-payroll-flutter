import { FieldValue, type Firestore } from 'firebase-admin/firestore';
import { AppError } from '../errors/app-error';
import type { LeaveTypeRecord, LeaveTypeStore } from './leave-type-service';

export class FirestoreLeaveTypeStore implements LeaveTypeStore {
  constructor(private readonly firestore: Firestore) {}

  serverTimestamp(): unknown {
    return FieldValue.serverTimestamp();
  }

  async listLeaveTypes(): Promise<LeaveTypeRecord[]> {
    const snapshot = await this.firestore.collection('leave_types').limit(100).get();
    return snapshot.docs.map((document) => ({
      ...document.data(),
      id: document.id,
    }) as LeaveTypeRecord);
  }

  async getLeaveType(id: string): Promise<LeaveTypeRecord | undefined> {
    const snapshot = await this.firestore.collection('leave_types').doc(id).get();
    return snapshot.exists
      ? { ...snapshot.data(), id: snapshot.id } as LeaveTypeRecord
      : undefined;
  }

  async writeLeaveType(input: {
    id: string;
    before?: LeaveTypeRecord;
    after: LeaveTypeRecord;
    action: 'leaveType.create' | 'leaveType.update' | 'leaveType.deactivate' | 'leaveType.reactivate';
    by: string;
    createOnly: boolean;
  }): Promise<void> {
    const typeRef = this.firestore.collection('leave_types').doc(input.id);
    const auditRef = this.firestore.collection('audit_logs').doc();
    await this.firestore.runTransaction(async (transaction) => {
      const snapshot = await transaction.get(typeRef);
      const allTypes = await transaction.get(this.firestore.collection('leave_types'));
      if (input.createOnly && snapshot.exists) {
        throw new Error('Leave type id already exists.');
      }
      if (!input.createOnly && !snapshot.exists) {
        throw new Error('Leave type no longer exists.');
      }
      for (const candidate of allTypes.docs) {
        if (candidate.id === input.id) continue;
        const data = candidate.data();
        if (String(data.name ?? '').trim().toLocaleLowerCase() === input.after.name.trim().toLocaleLowerCase()) {
          throw new AppError(409, 'LEAVE_TYPE_NAME_EXISTS', 'A leave type already uses this name.');
        }
        if (String(data.code ?? '').toUpperCase() === input.after.code.toUpperCase()) {
          throw new AppError(409, 'LEAVE_TYPE_CODE_EXISTS', 'A leave type already uses this code.');
        }
      }
      transaction.set(typeRef, input.after, { merge: !input.createOnly });
      transaction.create(auditRef, {
        action: input.action,
        entity: 'leave_type',
        entityId: input.id,
        before: input.before ?? null,
        after: input.after,
        by: input.by,
        at: FieldValue.serverTimestamp(),
      });
    });
  }

  async countPendingRequests(leaveTypeId: string): Promise<number> {
    const snapshot = await this.firestore.collection('leave_requests')
      .where('leaveTypeId', '==', leaveTypeId)
      .where('status', '==', 'pending')
      .count()
      .get();
    return snapshot.data().count;
  }
}
