import { Router } from 'express';
import type { IdTokenVerifier } from '../middleware/auth';
import { createAuthMiddleware, requireRole } from '../middleware/auth';
import { AppError } from '../errors/app-error';
import type { UserProfile } from '../services/profile';
import { serialize } from '../services/serialize';

export interface MeRouteDependencies {
  verifyIdToken: IdTokenVerifier;
  getProfile: (uid: string) => Promise<UserProfile | undefined>;
}

export function createMeRouter(dependencies: MeRouteDependencies) {
  const router = Router();

  router.get(
    '/',
    createAuthMiddleware(dependencies.verifyIdToken),
    requireRole('admin', 'employee'),
    async (req, res) => {
      const user = req.user;
      if (!user) {
        throw new AppError(401, 'UNAUTHORIZED', 'A valid Bearer token is required.');
      }

      const profile = await dependencies.getProfile(user.uid);
      if (!profile) {
        throw new AppError(404, 'USER_NOT_FOUND', 'User profile was not found.');
      }
      if (profile.status !== 'active') {
        throw new AppError(403, 'ACCOUNT_INACTIVE', 'This account is inactive.');
      }
      if (profile.role !== user.role) {
        throw new AppError(403, 'ROLE_MISMATCH', 'The account role does not match its ID token.');
      }

      res.json(serialize({ ...profile, uid: user.uid }));
    },
  );

  return router;
}
