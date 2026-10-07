import { Router } from 'express';
import type { IdTokenVerifier } from '../middleware/auth';
import { createAuthMiddleware, requireRole } from '../middleware/auth';
import { validate } from '../middleware/validate';
import { serialize } from '../services/serialize';
import {
  toBranchDto,
  type BranchInput,
  type BranchRecord,
  type BranchStatus,
} from '../services/branch-service';
import {
  branchIdParamsSchema,
  createBranchSchema,
  listBranchesQuerySchema,
  patchBranchSchema,
} from './branch-schemas';

export interface BranchOperations {
  createBranch(input: BranchInput): Promise<BranchRecord>;
  listBranches(
    caller: { uid: string; role: string },
    status: BranchStatus | 'all',
  ): Promise<BranchRecord[]>;
  getBranch(id: string, caller: { uid: string; role: string }): Promise<BranchRecord>;
  updateBranch(
    id: string,
    changes: Partial<BranchInput>,
    editedBy: string,
  ): Promise<BranchRecord>;
  deactivateBranch(id: string): Promise<BranchRecord>;
  reactivateBranch(id: string): Promise<BranchRecord>;
}

export interface BranchRouteDependencies {
  verifyIdToken: IdTokenVerifier;
  branches: BranchOperations;
}

export function createBranchesRouter(dependencies: BranchRouteDependencies) {
  const router = Router();
  const authenticate = createAuthMiddleware(dependencies.verifyIdToken);
  const admin = requireRole('admin');
  const signedIn = requireRole('admin', 'employee');

  router.post(
    '/',
    authenticate,
    admin,
    validate(createBranchSchema),
    async (_req, res) => {
      const branch = await dependencies.branches.createBranch(
        res.locals.validatedParts.body,
      );
      res.status(201).json(serialize(toBranchDto(branch)));
    },
  );

  router.get(
    '/',
    authenticate,
    signedIn,
    validate(listBranchesQuerySchema, 'query'),
    async (req, res) => {
      const { status } = res.locals.validatedParts.query;
      const branches = await dependencies.branches.listBranches(
        { uid: req.user!.uid, role: req.user!.role },
        status,
      );
      res.json(serialize(branches.map(toBranchDto)));
    },
  );

  router.get(
    '/:id',
    authenticate,
    signedIn,
    validate(branchIdParamsSchema, 'params'),
    async (req, res) => {
      const { id } = res.locals.validatedParts.params;
      const branch = await dependencies.branches.getBranch(id, {
        uid: req.user!.uid,
        role: req.user!.role,
      });
      res.json(serialize(toBranchDto(branch)));
    },
  );

  router.patch(
    '/:id',
    authenticate,
    admin,
    validate(branchIdParamsSchema, 'params'),
    validate(patchBranchSchema),
    async (req, res) => {
      const { id } = res.locals.validatedParts.params;
      const branch = await dependencies.branches.updateBranch(
        id,
        res.locals.validatedParts.body,
        req.user!.uid,
      );
      res.json(serialize(toBranchDto(branch)));
    },
  );

  router.post(
    '/:id/deactivate',
    authenticate,
    admin,
    validate(branchIdParamsSchema, 'params'),
    async (_req, res) => {
      const { id } = res.locals.validatedParts.params;
      const branch = await dependencies.branches.deactivateBranch(id);
      res.json(serialize(toBranchDto(branch)));
    },
  );

  router.post(
    '/:id/reactivate',
    authenticate,
    admin,
    validate(branchIdParamsSchema, 'params'),
    async (_req, res) => {
      const { id } = res.locals.validatedParts.params;
      const branch = await dependencies.branches.reactivateBranch(id);
      res.json(serialize(toBranchDto(branch)));
    },
  );

  return router;
}
