import { Router } from 'express';
import type { IdTokenVerifier } from '../middleware/auth';
import { createAuthMiddleware, requireRole } from '../middleware/auth';
import { validate } from '../middleware/validate';
import { serialize } from '../services/serialize';
import type { HolidayDto } from '../services/holiday-service';
import { createHolidaySchema, holidayIdParamsSchema, holidayMeQuerySchema, holidayYearQuerySchema } from './holiday-schemas';

export interface HolidayOperations {
  listHolidays(caller: { uid: string; role: string }, year: string, branchId?: string): Promise<HolidayDto[]>;
  listMine(caller: { uid: string; role: string }, year: string): Promise<HolidayDto[]>;
  createHoliday(caller: { uid: string; role: string }, input: { date: string; name: string; scope: 'all' | 'branches'; branchIds?: string[]; state?: string }): Promise<HolidayDto>;
  deleteHoliday(caller: { uid: string; role: string }, id: string): Promise<void>;
}
export function createHolidaysRouter(dependencies: { verifyIdToken: IdTokenVerifier; holidays: HolidayOperations }) {
  const router = Router();
  const authenticate = createAuthMiddleware(dependencies.verifyIdToken);
  router.get('/me', authenticate, requireRole('employee'), validate(holidayMeQuerySchema, 'query'), async (req, res) => {
    const { year } = res.locals.validatedParts.query;
    res.json(serialize(await dependencies.holidays.listMine({ uid: req.user!.uid, role: req.user!.role }, year)));
  });
  router.get('/', authenticate, requireRole('admin', 'employee'), validate(holidayYearQuerySchema, 'query'), async (req, res) => {
    const { year, branchId } = res.locals.validatedParts.query;
    res.json(serialize(await dependencies.holidays.listHolidays({ uid: req.user!.uid, role: req.user!.role }, year, branchId)));
  });
  router.post('/', authenticate, requireRole('admin'), validate(createHolidaySchema), async (req, res) => {
    const holiday = await dependencies.holidays.createHoliday({ uid: req.user!.uid, role: req.user!.role }, res.locals.validatedParts.body);
    res.status(201).json(serialize(holiday));
  });
  router.delete('/:id', authenticate, requireRole('admin'), validate(holidayIdParamsSchema, 'params'), async (req, res) => {
    const { id } = res.locals.validatedParts.params;
    await dependencies.holidays.deleteHoliday({ uid: req.user!.uid, role: req.user!.role }, id);
    res.status(204).end();
  });
  return router;
}
