import { z } from 'zod';

export const emptySettingsQuerySchema = z.strictObject({});

export const patchSettingsSchema = z
  .strictObject({
    companyName: z.string().trim().max(120).optional(),
    weeklyOffDays: z
      .array(z.number().int().min(0).max(6))
      .refine((days) => new Set(days).size === days.length, 'Weekdays must be unique.')
      .optional(),
    perDayBasis: z.enum(['calendar', 'working']).optional(),
    maxAccuracyMeters: z.number().int().min(10).max(500).optional(),
    rejectMockLocation: z.boolean().optional(),
    enforceCheckoutLocation: z.boolean().optional(),
  })
  .refine((settings) => Object.keys(settings).length > 0, {
    message: 'At least one setting must be provided.',
  });
