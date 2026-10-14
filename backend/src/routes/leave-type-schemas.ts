import { z } from 'zod';

const name = z.string().trim().min(1).max(50);
const code = z.string().regex(/^[A-Z0-9]{1,6}$/);
const quota = z.number().nullable().refine((value) => value === null ||
  (value >= 0.5 && value <= 366 && Number.isInteger(value * 2)));

export const leaveTypeParamsSchema = z.strictObject({ id: z.string().trim().min(1) });
export const leaveTypeListQuerySchema = z.strictObject({
  status: z.enum(['active', 'inactive', 'all']).default('all'),
});
export const leaveTypeCreateBodySchema = z.strictObject({
  name,
  code,
  paid: z.boolean(),
  annualQuotaDays: quota,
  allowHalfDay: z.boolean(),
  sortOrder: z.number().int().min(0).max(1000).optional(),
});
export const leaveTypePatchBodySchema = z.strictObject({
  name: name.optional(),
  code: code.optional(),
  paid: z.boolean().optional(),
  annualQuotaDays: quota.optional(),
  allowHalfDay: z.boolean().optional(),
  sortOrder: z.number().int().min(0).max(1000).optional(),
}).refine((value) => Object.keys(value).length > 0, 'At least one field must be provided.');
