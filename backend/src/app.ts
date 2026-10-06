import express from 'express';
import cors from 'cors';
import { healthRouter } from './routes/health';
import { createMeRouter, type MeRouteDependencies } from './routes/me';
import { AppError } from './errors/app-error';
import { errorHandler } from './middleware/error-handler';

export function createApp(dependencies: MeRouteDependencies) {
  const app = express();

  app.use(cors());
  app.use(express.json());

  app.use('/health', healthRouter);
  app.use('/me', createMeRouter(dependencies));

  app.use((_req, _res, next) => {
    next(new AppError(404, 'NOT_FOUND', 'Not found.'));
  });
  app.use(errorHandler);

  return app;
}
