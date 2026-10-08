import { Router } from 'express';
import type { IdTokenVerifier } from '../middleware/auth';
import { createAuthMiddleware, requireRole } from '../middleware/auth';
import { validate } from '../middleware/validate';
import { serialize } from '../services/serialize';
import type { HolidayRecord } from '../services/holiday-service';
import {
  createHolidaySchema,
  holidayDateParamsSchema,
  holidayYearQuerySchema,
} from './holiday-schemas';

export interface HolidayOperations {
  listHolidays(caller: { role: string }, year: string): Promise<HolidayRecord[]>;
  createHoliday(
    caller: { role: string },
    input: { date: string; name: string },
  ): Promise<HolidayRecord>;
  deleteHoliday(caller: { role: string }, date: string): Promise<void>;
}

export function createHolidaysRouter(dependencies: {
  verifyIdToken: IdTokenVerifier;
  holidays: HolidayOperations;
}) {
  const router = Router();
  const authenticate = createAuthMiddleware(dependencies.verifyIdToken);
  const admin = requireRole('admin');
  const signedIn = requireRole('admin', 'employee');

  router.get(
    '/',
    authenticate,
    signedIn,
    validate(holidayYearQuerySchema, 'query'),
    async (req, res) => {
      const { year } = res.locals.validatedParts.query;
      res.json(
        serialize(
          await dependencies.holidays.listHolidays(
            { role: req.user!.role },
            year,
          ),
        ),
      );
    },
  );

  router.post(
    '/',
    authenticate,
    admin,
    validate(createHolidaySchema),
    async (req, res) => {
      const holiday = await dependencies.holidays.createHoliday(
        { role: req.user!.role },
        res.locals.validatedParts.body,
      );
      res.status(201).json(serialize(holiday));
    },
  );

  router.delete(
    '/:date',
    authenticate,
    admin,
    validate(holidayDateParamsSchema, 'params'),
    async (req, res) => {
      const { date } = res.locals.validatedParts.params;
      await dependencies.holidays.deleteHoliday({ role: req.user!.role }, date);
      res.status(204).end();
    },
  );

  return router;
}
