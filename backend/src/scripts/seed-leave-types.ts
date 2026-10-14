import { FieldValue } from 'firebase-admin/firestore';
import { db } from '../config/firebase';
import { seedMissingLeaveTypes } from './seed-leave-types-core';

async function main() {
  const result = await seedMissingLeaveTypes({
    get: async (id) => (await db.collection('leave_types').doc(id).get()).exists,
    create: async (id, value) => { await db.collection('leave_types').doc(id).create(value); },
    timestamp: () => FieldValue.serverTimestamp(),
  });
  console.log(`Created leave type ids: ${result.created.join(', ') || '(none)'}`);
  console.log(`Skipped existing leave type ids: ${result.skipped.join(', ') || '(none)'}`);
}

if (process.argv[1]?.endsWith('seed-leave-types.ts')) {
  void main().catch((error: unknown) => {
    const code = typeof error === 'object' && error !== null && 'code' in error ? ` (${String(error.code)})` : '';
    console.error(`Leave type seeding failed${code}.`);
    process.exitCode = 1;
  });
}
