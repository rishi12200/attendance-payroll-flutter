import { Router } from 'express';
import type { IdTokenVerifier } from '../middleware/auth';
import { createAuthMiddleware, requireRole } from '../middleware/auth';
import { validate } from '../middleware/validate';
import { serialize } from '../services/serialize';
import type { PunchInput } from '../services/attendance-store';
import { attendanceMonthQuerySchema, punchBodySchema } from './attendance-schemas';

export interface AttendanceOperations {
  checkIn(caller: { uid: string; role: string }, input: PunchInput): Promise<Record<string, unknown>>;
  checkOut(caller: { uid: string; role: string }, input: PunchInput): Promise<Record<string, unknown>>;
  getMyAttendance(
    caller: { uid: string; role: string },
    month: string,
  ): Promise<Record<string, unknown>>;
}

export function createAttendanceRouter(dependencies: {
  verifyIdToken: IdTokenVerifier;
  attendance: AttendanceOperations;
}) {
  const router = Router();
  const authenticate = createAuthMiddleware(dependencies.verifyIdToken);
  const employee = requireRole('employee');

  router.post(
    '/check-in',
    authenticate,
    employee,
    validate(punchBodySchema),
    async (req, res) => {
      const result = await dependencies.attendance.checkIn(
        { uid: req.user!.uid, role: req.user!.role },
        res.locals.validatedParts.body,
      );
      res.status(201).json(serialize(result));
    },
  );

  router.post(
    '/check-out',
    authenticate,
    employee,
    validate(punchBodySchema),
    async (req, res) => {
      const result = await dependencies.attendance.checkOut(
        { uid: req.user!.uid, role: req.user!.role },
        res.locals.validatedParts.body,
      );
      res.json(serialize(result));
    },
  );

  router.get(
    '/me',
    authenticate,
    employee,
    validate(attendanceMonthQuerySchema, 'query'),
    async (req, res) => {
      const { month } = res.locals.validatedParts.query;
      const result = await dependencies.attendance.getMyAttendance(
        { uid: req.user!.uid, role: req.user!.role },
        month,
      );
      res.json(serialize(result));
    },
  );

  return router;
}
