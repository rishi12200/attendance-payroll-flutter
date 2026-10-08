import { Router } from 'express';
import type { IdTokenVerifier } from '../middleware/auth';
import { createAuthMiddleware, requireRole } from '../middleware/auth';
import { validate } from '../middleware/validate';
import { serialize } from '../services/serialize';
import {
  attendanceCalendarQuerySchema,
  attendanceDateQuerySchema,
  attendanceSummaryQuerySchema,
  editAttendanceBodySchema,
  editAttendanceParamsSchema,
  employeeAttendanceParamsSchema,
} from './attendance-view-schemas';

export interface AttendanceViewsOperations {
  getMyCalendar(
    caller: { uid: string; role: string },
    month: string,
  ): Promise<Record<string, unknown>>;
  getEmployeeCalendar(
    caller: { role: string },
    uid: string,
    month: string,
  ): Promise<Record<string, unknown>>;
  getSummary(
    caller: { uid: string; role: string },
    month: string,
    empId?: string,
  ): Promise<Record<string, unknown> | Array<Record<string, unknown>>>;
  getByDate(
    caller: { role: string },
    date: string,
  ): Promise<Record<string, unknown>>;
  editAttendance(input: {
    caller: { uid: string; role: string };
    empId: string;
    date: string;
    status: 'P' | 'H' | 'A' | 'L' | 'UL';
    inTime?: string;
    outTime?: string;
    reason: string;
  }): Promise<unknown>;
  getFlaggedCheckins(
    caller: { role: string },
    range: { from?: string; to?: string },
  ): Promise<Record<string, unknown>[]>;
}

export function createAttendanceViewsRouter(dependencies: {
  verifyIdToken: IdTokenVerifier;
  views: AttendanceViewsOperations;
}) {
  const router = Router();
  const authenticate = createAuthMiddleware(dependencies.verifyIdToken);
  const admin = requireRole('admin');
  const employee = requireRole('employee');
  const signedIn = requireRole('admin', 'employee');

  router.get(
    '/me/calendar',
    authenticate,
    employee,
    validate(attendanceCalendarQuerySchema, 'query'),
    async (req, res) => {
      const { month } = res.locals.validatedParts.query;
      res.json(
        serialize(
          await dependencies.views.getMyCalendar(
            { uid: req.user!.uid, role: req.user!.role },
            month,
          ),
        ),
      );
    },
  );

  router.get(
    '/employee/:id/calendar',
    authenticate,
    admin,
    validate(employeeAttendanceParamsSchema, 'params'),
    validate(attendanceCalendarQuerySchema, 'query'),
    async (req, res) => {
      const { id } = res.locals.validatedParts.params;
      const { month } = res.locals.validatedParts.query;
      res.json(
        serialize(
          await dependencies.views.getEmployeeCalendar(
            { role: req.user!.role },
            id,
            month,
          ),
        ),
      );
    },
  );

  router.get(
    '/summary',
    authenticate,
    signedIn,
    validate(attendanceSummaryQuerySchema, 'query'),
    async (req, res) => {
      const { month, empId } = res.locals.validatedParts.query;
      res.json(
        serialize(
          await dependencies.views.getSummary(
            { uid: req.user!.uid, role: req.user!.role },
            month,
            empId,
          ),
        ),
      );
    },
  );

  router.get(
    '/',
    authenticate,
    admin,
    validate(attendanceDateQuerySchema, 'query'),
    async (_req, res) => {
      const { date } = res.locals.validatedParts.query;
      res.json(
        serialize(
          await dependencies.views.getByDate({ role: 'admin' }, date),
        ),
      );
    },
  );

  router.patch(
    '/:empId/:date',
    authenticate,
    admin,
    validate(editAttendanceParamsSchema, 'params'),
    validate(editAttendanceBodySchema),
    async (req, res) => {
      const { empId, date } = res.locals.validatedParts.params;
      res.json(
        serialize(
          await dependencies.views.editAttendance({
            caller: { uid: req.user!.uid, role: req.user!.role },
            empId,
            date,
            ...res.locals.validatedParts.body,
          }),
        ),
      );
    },
  );

  return router;
}
