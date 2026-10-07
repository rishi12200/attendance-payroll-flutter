import { z } from 'zod';

export const punchBodySchema = z.strictObject({
  lat: z.number().finite().min(-90).max(90),
  lng: z.number().finite().min(-180).max(180),
  accuracy: z.number().finite().min(0),
  deviceId: z.string().trim().min(1).max(100),
  isMocked: z.boolean(),
});

export const attendanceMonthQuerySchema = z.strictObject({
  month: z
    .string()
    .regex(/^\d{4}-(0[1-9]|1[0-2])$/, 'Expected a YYYY-MM month.'),
});

export type PunchBody = z.infer<typeof punchBodySchema>;
export type AttendanceMonthQuery = z.infer<typeof attendanceMonthQuerySchema>;
