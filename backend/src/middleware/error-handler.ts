import type { ErrorRequestHandler } from 'express';
import { AppError } from '../errors/app-error';

function isMalformedJsonError(error: unknown): boolean {
  return (
    typeof error === 'object' &&
    error !== null &&
    'type' in error &&
    error.type === 'entity.parse.failed'
  );
}

export const errorHandler: ErrorRequestHandler = (error, req, res, next) => {
  if (res.headersSent) {
    return next(error);
  }

  if (error instanceof AppError) {
    return res.status(error.status).json({
      error: {
        code: error.code,
        message: error.message,
        details: error.details,
      },
    });
  }

  if (isMalformedJsonError(error)) {
    return res.status(400).json({
      error: {
        code: 'VALIDATION_ERROR',
        message: 'Request body must contain valid JSON.',
        details: {},
      },
    });
  }

  console.error('Unhandled API error', {
    method: req.method,
    path: req.path,
    stack: error instanceof Error ? error.stack : undefined,
  });
  return res.status(500).json({
    error: {
      code: 'INTERNAL_SERVER_ERROR',
      message: 'An unexpected error occurred.',
      details: {},
    },
  });
};
