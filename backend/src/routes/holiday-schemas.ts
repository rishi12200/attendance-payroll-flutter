import { z } from 'zod';
import { isValidDateString } from '../domain/dates';

const date = z.string().refine(isValidDateString, 'Expected a valid YYYY-MM-DD date.');
export const holidayYearQuerySchema = z.strictObject({ year: z.string().regex(/^\d{4}$/), branchId: z.string().min(1).optional() });
export const holidayMeQuerySchema = z.strictObject({ year: z.string().regex(/^\d{4}$/) });
export const createHolidaySchema = z.strictObject({
  date, name: z.string().trim().min(1).max(120), scope: z.enum(['all', 'branches']),
  branchIds: z.array(z.string().min(1)).optional(), state: z.string().trim().min(1).optional(),
}).refine((value) => !(value.branchIds && value.state), { message: 'Choose branchIds or state, not both.', path: ['state'] });
export const holidayIdParamsSchema = z.strictObject({ id: z.string().min(1) });
