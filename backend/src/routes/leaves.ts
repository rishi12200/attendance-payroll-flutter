import { Router } from 'express';
import type { IdTokenVerifier } from '../middleware/auth';
import { createAuthMiddleware, requireRole } from '../middleware/auth';
import { validate } from '../middleware/validate';
import { AppError } from '../errors/app-error';
import { serialize } from '../services/serialize';
import {
  leaveApplyBodySchema,
  leaveBalanceQuerySchema,
  leaveDecisionBodySchema,
  leaveListQuerySchema,
  leaveMeQuerySchema,
  leaveParamsSchema,
} from './leave-schemas';

export interface LeaveOperations {
  apply(
    caller: { uid: string; role: string },
    input: { leaveTypeId: string; fromDate: string; toDate: string; reason: string; session: 'full' | 'first_half' | 'second_half' },
  ): Promise<unknown>;
  listMine(caller: { uid: string; role: string }, status?: string): Promise<unknown>;
  listAll(
    caller: { uid: string; role: string },
    input: { status: string; empId?: string },
  ): Promise<unknown>;
  getById(caller: { uid: string; role: string }, id: string): Promise<unknown>;
  cancel(caller: { uid: string; role: string }, id: string): Promise<unknown>;
  getBalance(caller: { uid: string; role: string }, input: { year?: number; empId?: string }): Promise<unknown>;
  decide(input: {
    caller: { uid: string; role: string };
    id: string;
    decision: 'approved' | 'rejected';
    note?: string;
  }): Promise<unknown>;
}

export function createLeavesRouter(dependencies: {
  verifyIdToken: IdTokenVerifier;
  leaves: LeaveOperations;
}) {
  const router = Router();
  const authenticate = createAuthMiddleware(dependencies.verifyIdToken);
  const admin = requireRole('admin');
  const employee = requireRole('employee');
  const signedIn = requireRole('admin', 'employee');
  const rejectDecisionLeaveType = (req: import('express').Request, _res: import('express').Response, next: import('express').NextFunction) => {
    if (typeof req.body === 'object' && req.body !== null && 'leaveType' in req.body) {
      return next(new AppError(400, 'VALIDATION_ERROR', "leaveType is no longer accepted; the request's leave type decides."));
    }
    return next();
  };

  router.post(
    '/',
    authenticate,
    employee,
    validate(leaveApplyBodySchema),
    async (req, res) => {
      res.status(201).json(
        serialize(
          await dependencies.leaves.apply(
            { uid: req.user!.uid, role: req.user!.role },
            res.locals.validatedParts.body,
          ),
        ),
      );
    },
  );

  router.get(
    '/me',
    authenticate,
    employee,
    validate(leaveMeQuerySchema, 'query'),
    async (req, res) => {
      const { status } = res.locals.validatedParts.query;
      res.json(
        serialize(
          await dependencies.leaves.listMine(
            { uid: req.user!.uid, role: req.user!.role },
            status,
          ),
        ),
      );
    },
  );

  router.get(
    '/balance',
    authenticate,
    signedIn,
    validate(leaveBalanceQuerySchema, 'query'),
    async (req, res) => {
      res.json(serialize(await dependencies.leaves.getBalance(
        { uid: req.user!.uid, role: req.user!.role },
        res.locals.validatedParts.query,
      )));
    },
  );

  router.post(
    '/:id/cancel',
    authenticate,
    employee,
    validate(leaveParamsSchema, 'params'),
    async (req, res) => {
      const { id } = res.locals.validatedParts.params;
      res.json(
        serialize(
          await dependencies.leaves.cancel(
            { uid: req.user!.uid, role: req.user!.role },
            id,
          ),
        ),
      );
    },
  );

  router.get(
    '/',
    authenticate,
    admin,
    validate(leaveListQuerySchema, 'query'),
    async (req, res) => {
      res.json(
        serialize(
          await dependencies.leaves.listAll(
            { uid: req.user!.uid, role: req.user!.role },
            res.locals.validatedParts.query,
          ),
        ),
      );
    },
  );

  router.get(
    '/:id',
    authenticate,
    signedIn,
    validate(leaveParamsSchema, 'params'),
    async (req, res) => {
      const { id } = res.locals.validatedParts.params;
      res.json(
        serialize(
          await dependencies.leaves.getById(
            { uid: req.user!.uid, role: req.user!.role },
            id,
          ),
        ),
      );
    },
  );

  router.post(
    '/:id/decision',
    authenticate,
    admin,
    validate(leaveParamsSchema, 'params'),
      rejectDecisionLeaveType,
    validate(leaveDecisionBodySchema),
    async (req, res) => {
      const { id } = res.locals.validatedParts.params;
      res.json(
        serialize(
          await dependencies.leaves.decide({
            caller: { uid: req.user!.uid, role: req.user!.role },
            id,
            ...res.locals.validatedParts.body,
          }),
        ),
      );
    },
  );

  return router;
}
