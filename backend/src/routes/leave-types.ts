import { Router } from 'express';
import type { IdTokenVerifier } from '../middleware/auth';
import { createAuthMiddleware, requireRole } from '../middleware/auth';
import { validate } from '../middleware/validate';
import { serialize } from '../services/serialize';
import {
  leaveTypeCreateBodySchema,
  leaveTypeListQuerySchema,
  leaveTypeParamsSchema,
  leaveTypePatchBodySchema,
} from './leave-type-schemas';

export interface LeaveTypeOperations {
  list(caller: { uid: string; role: string }, status: 'active' | 'inactive' | 'all'): Promise<unknown>;
  create(input: Record<string, unknown>, by: string): Promise<unknown>;
  update(id: string, changes: Record<string, unknown>, by: string): Promise<unknown>;
  deactivate(id: string, by: string): Promise<unknown>;
  reactivate(id: string, by: string): Promise<unknown>;
}

export function createLeaveTypesRouter(dependencies: {
  verifyIdToken: IdTokenVerifier;
  leaveTypes: LeaveTypeOperations;
}) {
  const router = Router();
  const authenticate = createAuthMiddleware(dependencies.verifyIdToken);
  const admin = requireRole('admin');
  const signedIn = requireRole('admin', 'employee');

  router.get('/', authenticate, signedIn, validate(leaveTypeListQuerySchema, 'query'), async (req, res) => {
    res.json(serialize(await dependencies.leaveTypes.list(
      { uid: req.user!.uid, role: req.user!.role },
      res.locals.validatedParts.query.status,
    )));
  });

  router.post('/', authenticate, admin, validate(leaveTypeCreateBodySchema), async (req, res) => {
    res.status(201).json(serialize(await dependencies.leaveTypes.create(
      res.locals.validatedParts.body,
      req.user!.uid,
    )));
  });

  router.patch('/:id', authenticate, admin, validate(leaveTypeParamsSchema, 'params'), validate(leaveTypePatchBodySchema), async (req, res) => {
    res.json(serialize(await dependencies.leaveTypes.update(
      res.locals.validatedParts.params.id,
      res.locals.validatedParts.body,
      req.user!.uid,
    )));
  });

  router.post('/:id/deactivate', authenticate, admin, validate(leaveTypeParamsSchema, 'params'), async (req, res) => {
    res.json(serialize(await dependencies.leaveTypes.deactivate(
      res.locals.validatedParts.params.id, req.user!.uid,
    )));
  });

  router.post('/:id/reactivate', authenticate, admin, validate(leaveTypeParamsSchema, 'params'), async (req, res) => {
    res.json(serialize(await dependencies.leaveTypes.reactivate(
      res.locals.validatedParts.params.id, req.user!.uid,
    )));
  });

  return router;
}
