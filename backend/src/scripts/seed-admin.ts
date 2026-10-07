import { FieldValue } from 'firebase-admin/firestore';
import { auth, db } from '../config/firebase';
import { parseSeedUserArguments } from './seed-admin-args';

function firebaseErrorCode(error: unknown): string | undefined {
  if (
    typeof error === 'object' &&
    error !== null &&
    'code' in error &&
    typeof error.code === 'string'
  ) {
    return error.code;
  }
  return undefined;
}

async function main() {
  const credentials = parseSeedUserArguments(process.argv.slice(2));
  if (!credentials) {
    console.error(
      'Usage: npm run seed:admin -- --email <email> --password <password> [--role admin|employee] (password must be at least 6 characters)',
    );
    process.exitCode = 1;
    return;
  }

  let uid: string;
  try {
    const user = await auth.createUser({
      email: credentials.email,
      password: credentials.password,
    });
    uid = user.uid;
  } catch (error) {
    const code = firebaseErrorCode(error);
    console.error(`Failed to create the admin Auth user${code ? ` (${code})` : ''}.`);
    process.exitCode = 1;
    return;
  }

  try {
    await auth.setCustomUserClaims(uid, { role: credentials.role });
    await db.collection('employees').doc(uid).create({
      name: credentials.email.split('@')[0],
      email: credentials.email,
      role: credentials.role,
      status: 'active',
      createdAt: FieldValue.serverTimestamp(),
    });
  } catch (error) {
    const code = firebaseErrorCode(error);
    console.error(
      `Auth user ${uid} was created, but profile setup did not complete${code ? ` (${code})` : ''}.`,
    );
    process.exitCode = 1;
    return;
  }

  console.log(`Seed ${credentials.role} account created and configured.`);
}

void main().catch((error: unknown) => {
  const code = firebaseErrorCode(error);
  console.error(`Admin seeding failed${code ? ` (${code})` : ''}.`);
  process.exitCode = 1;
});
