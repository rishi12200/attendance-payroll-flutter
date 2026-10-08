import { Router } from 'express';
import type { IdTokenVerifier } from '../middleware/auth';
import { createAuthMiddleware, requireRole } from '../middleware/auth';
import { validate } from '../middleware/validate';
import { serialize } from '../services/serialize';
import type { SettingsPatch } from '../services/settings-service';
import { emptySettingsQuerySchema, patchSettingsSchema } from './settings-schemas';

export interface SettingsOperations {
  getSettings(caller: { role: string }): Promise<Record<string, unknown>>;
  updateSettings(
    caller: { uid: string; role: string },
    changes: SettingsPatch,
  ): Promise<Record<string, unknown>>;
}

export function createSettingsRouter(dependencies: {
  verifyIdToken: IdTokenVerifier;
  settings: SettingsOperations;
}) {
  const router = Router();
  const authenticate = createAuthMiddleware(dependencies.verifyIdToken);
  const admin = requireRole('admin');

  router.get(
    '/',
    authenticate,
    admin,
    validate(emptySettingsQuerySchema, 'query'),
    async (req, res) => {
      res.json(
        serialize(
          await dependencies.settings.getSettings({
            role: req.user!.role,
          }),
        ),
      );
    },
  );

  router.patch(
    '/',
    authenticate,
    admin,
    validate(patchSettingsSchema),
    async (req, res) => {
      res.json(
        serialize(
          await dependencies.settings.updateSettings(
            { uid: req.user!.uid, role: req.user!.role },
            res.locals.validatedParts.body,
          ),
        ),
      );
    },
  );

  return router;
}
