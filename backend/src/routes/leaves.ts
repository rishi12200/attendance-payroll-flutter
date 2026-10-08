import { Router } from 'express';
import type { IdTokenVerifier } from '../middleware/auth';
import { createAuthMiddleware, requireRole } from '../middleware/auth';
import { validate } from '../middleware/validate';
import { serialize } from '../services/serialize';
import {
  leaveApplyBodySchema,
  leaveDecisionBodySchema,
  leaveListQuerySchema,
  leaveMeQuerySchema,
  leaveParamsSchema,
} from './leave-schemas';

export interface LeaveOperations {
  apply(
    caller: { uid: string; role: string },
    input: { fromDate: string; toDate: string; reason: string },
  ): Promise<unknown>;
  listMine(caller: { uid: string; role: string }, status?: string): Promise<unknown>;
  listAll(
    caller: { uid: string; role: string },
    input: { status: string; empId?: string },
  ): Promise<unknown>;
  getById(caller: { uid: string; role: string }, id: string): Promise<unknown>;
  cancel(caller: { uid: string; role: string }, id: string): Promise<unknown>;
  decide(input: {
    caller: { uid: string; role: string };
    id: string;
    decision: 'approved' | 'rejected';
    leaveType?: 'paid' | 'unpaid';
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
