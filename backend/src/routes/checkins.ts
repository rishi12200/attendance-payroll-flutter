import { Router } from 'express';
import type { IdTokenVerifier } from '../middleware/auth';
import { createAuthMiddleware, requireRole } from '../middleware/auth';
import { validate } from '../middleware/validate';
import { serialize } from '../services/serialize';
import type { AttendanceViewsOperations } from './attendance-views';
import { flaggedCheckinsQuerySchema } from './attendance-view-schemas';

export function createCheckinsRouter(dependencies: {
  verifyIdToken: IdTokenVerifier;
  views: Pick<AttendanceViewsOperations, 'getFlaggedCheckins'>;
}) {
  const router = Router();
  const authenticate = createAuthMiddleware(dependencies.verifyIdToken);
  const admin = requireRole('admin');

  router.get(
    '/flagged',
    authenticate,
    admin,
    validate(flaggedCheckinsQuerySchema, 'query'),
    async (req, res) => {
      res.json(
        serialize(
          await dependencies.views.getFlaggedCheckins(
            { role: req.user!.role },
            res.locals.validatedParts.query,
          ),
        ),
      );
    },
  );

  return router;
}
