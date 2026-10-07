import type { RequestHandler } from 'express';
import type { z } from 'zod';
import { AppError } from '../errors/app-error';

type RequestPart = 'body' | 'params' | 'query';

export function validate<TSchema extends z.ZodType>(
  schema: TSchema,
  part: RequestPart = 'body',
): RequestHandler {
  return (req, res, next) => {
    const result = schema.safeParse(req[part]);
    if (!result.success) {
      return next(
        new AppError(400, 'VALIDATION_ERROR', 'Request validation failed.', {
          issues: result.error.issues.map((issue) => ({
            path: issue.path.map(String).join('.'),
            message: issue.message,
          })),
        }),
      );
    }

    res.locals.validated = result.data;
    return next();
  };
}
