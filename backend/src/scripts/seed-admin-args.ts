import { z } from 'zod';

export type SeedUserRole = 'admin' | 'employee';

export interface SeedUserArguments {
  email: string;
  password: string;
  role: SeedUserRole;
}

export function parseSeedUserArguments(args: string[]): SeedUserArguments | undefined {
  const values = new Map<string, string>();
  for (let index = 0; index < args.length; index += 2) {
    const option = args[index];
    const value = args[index + 1];
    if (
      !['--email', '--password', '--role'].includes(option) ||
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
  const role = values.get('--role') ?? 'admin';
  if (
    email === undefined ||
    password === undefined ||
    !z.string().email().safeParse(email).success ||
    password.length < 6 ||
    (role !== 'admin' && role !== 'employee')
  ) {
    return undefined;
  }

  return { email, password, role };
}
