import { auth, db, projectId } from '../config/firebase';

async function main() {
  console.log(`Project: ${projectId}\n`);

  try {
    const users = await auth.listUsers(1);
    console.log(`[OK] Auth reachable (users found in first page: ${users.users.length})`);
  } catch (e: any) {
    console.error('[FAIL] Auth:', e.message);
    console.error('  - Is Authentication enabled in the Firebase console?');
    process.exit(1);
  }

  try {
    const ref = db.collection('_healthcheck').doc('ping');
    await ref.set({ at: new Date().toISOString() });
    const snap = await ref.get();
    await ref.delete();
    console.log(`[OK] Firestore read/write works (doc existed: ${snap.exists})`);
  } catch (e: any) {
    console.error('[FAIL] Firestore:', e.message);
    console.error('  - Is the Firestore database created in the Firebase console?');
    process.exit(1);
  }

  console.log('\nAll checks passed.');
  process.exit(0);
}

main();
