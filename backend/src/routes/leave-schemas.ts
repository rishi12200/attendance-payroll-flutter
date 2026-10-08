import { z } from 'zod';
import { isValidDateString } from '../domain/dates';

const date = z.string().refine(isValidDateString, 'Expected a valid YYYY-MM-DD date.');
const requestStatus = z.enum(['pending', 'approved', 'rejected', 'cancelled']);

export const leaveParamsSchema = z.strictObject({
  id: z.string().trim().min(1),
});

export const leaveApplyBodySchema = z.strictObject({
  fromDate: date,
  toDate: date,
  reason: z.string().trim().min(1).max(200),
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
    leaveType: z.enum(['paid', 'unpaid']).optional(),
    note: z.string().trim().max(200).optional(),
  })
  .refine(
    ({ decision, leaveType }) => decision === 'rejected' || leaveType !== undefined,
    { message: 'leaveType is required when approving a leave request.', path: ['leaveType'] },
  )
  .refine(
    ({ decision, leaveType }) => decision === 'approved' || leaveType === undefined,
    { message: 'leaveType is only allowed when approving a leave request.', path: ['leaveType'] },
  );
