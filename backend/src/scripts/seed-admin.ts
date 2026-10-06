import { z } from 'zod';
import { FieldValue } from 'firebase-admin/firestore';
import { auth, db } from '../config/firebase';

interface AdminCredentials {
  email: string;
  password: string;
}

function parseArguments(args: string[]): AdminCredentials | undefined {
  if (args.length !== 4) {
    return undefined;
  }

  const values = new Map<string, string>();
  for (let index = 0; index < args.length; index += 2) {
    const option = args[index];
    const value = args[index + 1];
    if (
      (option !== '--email' && option !== '--password') ||
      value === undefined ||
      value.startsWith('--') ||
      values.has(option)
    ) {
      return undefined;
    }
    values.set(option, value);
  }

  const email = values.get('--email');
  const password = values.get('--password');
  if (
    email === undefined ||
    password === undefined ||
    !z.string().email().safeParse(email).success ||
    password.length < 6
  ) {
    return undefined;
  }

  return { email, password };
}

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
  const credentials = parseArguments(process.argv.slice(2));
  if (!credentials) {
    console.error(
      'Usage: npm run seed:admin -- --email <email> --password <password> (password must be at least 6 characters)',
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
    await auth.setCustomUserClaims(uid, { role: 'admin' });
    await db.collection('employees').doc(uid).create({
      name: credentials.email.split('@')[0],
      email: credentials.email,
      role: 'admin',
      status: 'active',
      createdAt: FieldValue.serverTimestamp(),
    });
  } catch (error) {
    const code = firebaseErrorCode(error);
    console.error(
      `Auth user ${uid} was created, but admin setup did not complete${code ? ` (${code})` : ''}.`,
    );
    process.exitCode = 1;
    return;
  }

  console.log('Admin account created and configured.');
}

void main().catch((error: unknown) => {
  const code = firebaseErrorCode(error);
  console.error(`Admin seeding failed${code ? ` (${code})` : ''}.`);
  process.exitCode = 1;
});
