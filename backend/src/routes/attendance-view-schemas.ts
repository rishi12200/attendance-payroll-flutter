import { z } from 'zod';
import { isValidDateString } from '../domain/dates';

const date = z.string().refine(isValidDateString, 'Expected a valid YYYY-MM-DD date.');
const month = z
  .string()
  .regex(/^\d{4}-(0[1-9]|1[0-2])$/, 'Expected a YYYY-MM month.');
const isoDateTime = z.string().refine(
  (value) =>
    Number.isFinite(Date.parse(value)) &&
    /T.*(?:Z|[+-]\d{2}:\d{2})$/i.test(value),
  'Expected an ISO 8601 timestamp with a timezone.',
);

export const employeeAttendanceParamsSchema = z.strictObject({
  id: z.string().trim().min(1),
});

export const attendanceDateQuerySchema = z.strictObject({ date });
export const attendanceCalendarQuerySchema = z.strictObject({ month });

export const attendanceSummaryQuerySchema = z.strictObject({
  month,
  empId: z.string().trim().min(1).optional(),
});

export const editAttendanceParamsSchema = z.strictObject({
  empId: z.string().trim().min(1),
  date,
});

export const editAttendanceBodySchema = z
  .strictObject({
    status: z.enum(['P', 'H', 'A', 'L', 'UL']),
    inTime: isoDateTime.optional(),
    outTime: isoDateTime.optional(),
    reason: z.string().trim().min(1).max(200),
  })
  .refine(
    (input) =>
      (input.status === 'P' || input.status === 'H') ||
      (input.inTime === undefined && input.outTime === undefined),
    { message: 'Times are only allowed with status P or H.' },
  );

export const flaggedCheckinsQuerySchema = z
  .strictObject({ from: date.optional(), to: date.optional() })
  .refine(
    ({ from, to }) => from === undefined || to === undefined || from <= to,
    { message: 'The from date must not be after the to date.' },
  );
