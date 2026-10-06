import 'dotenv/config';
import path from 'path';
import { z } from 'zod';

const schema = z.object({
  PORT: z.coerce.number().default(8080),
  NODE_ENV: z.enum(['development', 'production', 'test']).default('development'),
  GOOGLE_APPLICATION_CREDENTIALS: z.string().optional(),
});

const parsed = schema.safeParse(process.env);
if (!parsed.success) {
  console.error('Invalid environment variables:', parsed.error.flatten().fieldErrors);
  process.exit(1);
}

export const env = {
  ...parsed.data,
  credentialsPath: parsed.data.GOOGLE_APPLICATION_CREDENTIALS
    ? path.resolve(process.cwd(), parsed.data.GOOGLE_APPLICATION_CREDENTIALS)
    : undefined,
};
