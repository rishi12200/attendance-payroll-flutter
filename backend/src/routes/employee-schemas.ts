import { z } from 'zod';
import { isValidDateString } from '../domain/dates';

const dateString = z.string().refine(isValidDateString, 'Expected a valid YYYY-MM-DD date.');
const optionalTrimmedText = z.string().trim().optional();
const positiveInteger = z.number().int().positive();
const branchIds = z
  .array(z.string().trim().min(1))
  .max(20)
  .refine((ids) => new Set(ids).size === ids.length, 'Branch IDs must be unique.');

export const createEmployeeSchema = z.strictObject({
  name: z.string().trim().min(1),
  email: z.email().trim().toLowerCase(),
  tempPassword: z.string().min(8),
  phone: optionalTrimmedText,
  designation: optionalTrimmedText,
  doj: dateString,
  monthlyCtcPaise: positiveInteger,
  primaryBranchId: z.string().trim().min(1).nullable().optional(),
  allowedBranchIds: branchIds.optional(),
});

export const patchEmployeeSchema = z
  .strictObject({
    name: z.string().trim().min(1).optional(),
    phone: optionalTrimmedText,
    designation: optionalTrimmedText,
    doj: dateString.optional(),
    primaryBranchId: z.string().trim().min(1).nullable().optional(),
    allowedBranchIds: branchIds.optional(),
  })
  .refine((value) => Object.keys(value).length > 0, 'At least one editable field is required.');

export const salaryRevisionSchema = z.strictObject({
  effectiveFrom: dateString,
  monthlyCtcPaise: positiveInteger,
});

export const employeeIdParamsSchema = z.strictObject({
  id: z.string().trim().min(1),
});

export const listEmployeesQuerySchema = z.strictObject({
  status: z.enum(['active', 'inactive', 'all']).default('active'),
});

export const deactivateEmployeeSchema = z
  .strictObject({
    dol: dateString.optional(),
  })
  .default({});

export type CreateEmployeeInput = z.infer<typeof createEmployeeSchema>;
export type PatchEmployeeInput = z.infer<typeof patchEmployeeSchema>;
export type SalaryRevisionInput = z.infer<typeof salaryRevisionSchema>;
export type DeactivateEmployeeInput = z.infer<typeof deactivateEmployeeSchema>;
