import { FieldValue, type Firestore } from 'firebase-admin/firestore';
import type { BranchRecord, BranchStore } from './branch-service';

export class FirestoreBranchStore implements BranchStore {
  constructor(private readonly firestore: Firestore) {}

  serverTimestamp(): unknown {
    return FieldValue.serverTimestamp();
  }

  async listBranches(): Promise<BranchRecord[]> {
    const snapshot = await this.firestore.collection('branches').get();
    return snapshot.docs.map((document) => ({
      ...(document.data() as BranchRecord),
      id: document.id,
    }));
  }

  async getBranch(id: string): Promise<BranchRecord | undefined> {
    const snapshot = await this.firestore.collection('branches').doc(id).get();
    return snapshot.exists
      ? {
          ...(snapshot.data() as BranchRecord),
          id: snapshot.id,
        }
      : undefined;
  }

  async createBranch(branch: Record<string, unknown>): Promise<string> {
    const reference = this.firestore.collection('branches').doc();
    await reference.create(branch);
    return reference.id;
  }

  async updateBranch(id: string, values: Record<string, unknown>): Promise<void> {
    await this.firestore.collection('branches').doc(id).update(values);
  }
}
