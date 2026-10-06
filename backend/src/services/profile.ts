import { db } from '../config/firebase';

export type UserProfile = Record<string, unknown>;

export async function getUserProfile(uid: string): Promise<UserProfile | undefined> {
  const snapshot = await db.collection('employees').doc(uid).get();
  return snapshot.exists ? snapshot.data() : undefined;
}
