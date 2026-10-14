import { z } from 'zod';
import { isValidDateString } from '../domain/dates';

const date = z.string().refine(isValidDateString, 'Expected a valid YYYY-MM-DD date.');
const requestStatus = z.enum(['pending', 'approved', 'rejected', 'cancelled']);

export const leaveParamsSchema = z.strictObject({
  id: z.string().trim().min(1),
});

export const leaveBalanceQuerySchema = z.strictObject({
  year: z.coerce.number().int().min(2000).max(2100).optional(),
  empId: z.string().trim().min(1).optional(),
});

export const leaveApplyBodySchema = z.strictObject({
  leaveTypeId: z.string().trim().min(1),
  fromDate: date,
  toDate: date,
  reason: z.string().trim().min(1).max(200),
  session: z.enum(['full', 'first_half', 'second_half']).default('full'),
});

export const leaveMeQuerySchema = z.strictObject({
  status: z.union([requestStatus, z.literal('all')]).optional(),
});

export const leaveListQuerySchema = z.strictObject({
  status: z.union([requestStatus, z.literal('all')]).default('pending'),
  empId: z.string().trim().min(1).optional(),
});

export const leaveDecisionBodySchema = z
  .strictObject({
    decision: z.enum(['approved', 'rejected']),
    note: z.string().trim().max(200).optional(),
  });
