import { z } from 'zod';
import { isValidDateString } from '../domain/dates';

const date = z.string().refine(isValidDateString, 'Expected a valid YYYY-MM-DD date.');

export const holidayYearQuerySchema = z.strictObject({
  year: z.string().regex(/^\d{4}$/, 'Expected a four-digit year.'),
});

export const createHolidaySchema = z.strictObject({
  date,
  name: z.string().trim().min(1).max(120),
});

export const holidayDateParamsSchema = z.strictObject({ date });
