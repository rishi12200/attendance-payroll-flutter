import { z } from 'zod';

interface LoginCredentials {
  email: string;
  password: string;
}

interface FirebaseLoginResponse {
  idToken?: unknown;
}

export function parseLoginArguments(args: string[]): LoginCredentials | undefined {
  if (args.length !== 4) return undefined;
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
    password.length === 0
  ) {
    return undefined;
  }
  return { email, password };
}

export async function fetchIdToken(
  credentials: LoginCredentials,
  apiKey: string,
  fetcher: typeof fetch = fetch,
): Promise<string> {
  const endpoint = new URL(
    'https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword',
  );
  endpoint.searchParams.set('key', apiKey);

  let response: Response;
  try {
    response = await fetcher(endpoint, {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({
        email: credentials.email,
        password: credentials.password,
        returnSecureToken: true,
      }),
    });
  } catch {
    throw new Error('Firebase sign-in request failed.');
  }

  if (!response.ok) {
    throw new Error(`Firebase sign-in failed (HTTP ${response.status}).`);
  }

  let payload: FirebaseLoginResponse;
  try {
    payload = (await response.json()) as FirebaseLoginResponse;
  } catch {
    throw new Error('Firebase returned an invalid sign-in response.');
  }
  if (typeof payload.idToken !== 'string' || payload.idToken.length === 0) {
    throw new Error('Firebase response did not contain an ID token.');
  }
  return payload.idToken;
}

async function main() {
  const credentials = parseLoginArguments(process.argv.slice(2));
  if (!credentials) {
    console.error('Usage: npm run dev:login -- --email <email> --password <password>');
    process.exitCode = 1;
    return;
  }
  const apiKey = process.env.WEB_API_KEY;
  if (!apiKey) {
    console.error('Set WEB_API_KEY in the environment before using dev:login.');
    process.exitCode = 1;
    return;
  }

  try {
    process.stdout.write(`${await fetchIdToken(credentials, apiKey)}\n`);
  } catch (error) {
    console.error(error instanceof Error ? error.message : 'Firebase sign-in failed.');
    process.exitCode = 1;
  }
}

if (process.argv[1]?.endsWith('dev-login.ts')) {
  void main();
}
