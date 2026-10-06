import type { DecodedIdToken } from 'firebase-admin/auth';
import type { NextFunction, Request, Response } from 'express';
import { AppError } from '../errors/app-error';

export type IdTokenVerifier = (
  token: string,
  checkRevoked: boolean,
) => Promise<DecodedIdToken>;

declare global {
  namespace Express {
    interface Request {
      user?: DecodedIdToken;
    }
  }
}

const tokenErrorCodes = new Set([
  'auth/argument-error',
  'auth/id-token-expired',
  'auth/id-token-revoked',
  'auth/invalid-id-token',
  'auth/user-disabled',
  'auth/user-not-found',
]);

function isTokenVerificationError(error: unknown): boolean {
  if (typeof error !== 'object' || error === null || !('code' in error)) {
    return false;
  }

  return typeof error.code === 'string' && tokenErrorCodes.has(error.code);
}

export function createAuthMiddleware(verifyIdToken: IdTokenVerifier) {
  return async (req: Request, _res: Response, next: NextFunction) => {
    const authorization = req.get('authorization');
    const match = authorization?.match(/^Bearer\s+(\S+)$/i);

    if (!match) {
      return next(
        new AppError(
          401,
          'UNAUTHORIZED',
          'A valid Bearer token is required.',
        ),
      );
    }

    try {
      req.user = await verifyIdToken(match[1], true);
      return next();
    } catch (error) {
      if (isTokenVerificationError(error)) {
        return next(
          new AppError(401, 'INVALID_TOKEN', 'The ID token is invalid or expired.'),
        );
      }

      return next(error);
    }
  };
}

export function requireRole(...allowedRoles: Array<'admin' | 'employee'>) {
  const roles = new Set<string>(allowedRoles);

  return (req: Request, _res: Response, next: NextFunction) => {
    const role = req.user?.role;
    if (typeof role !== 'string' || !roles.has(role)) {
      return next(
        new AppError(403, 'FORBIDDEN', 'You do not have permission to access this resource.'),
      );
    }

    return next();
  };
}
