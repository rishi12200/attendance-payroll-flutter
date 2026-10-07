import express from 'express';
import cors from 'cors';
import { healthRouter } from './routes/health';
import { createMeRouter, type MeRouteDependencies } from './routes/me';
import { AppError } from './errors/app-error';
import { errorHandler } from './middleware/error-handler';
import { createEmployeesRouter, type EmployeeOperations } from './routes/employees';
import { createBranchesRouter, type BranchOperations } from './routes/branches';
import { createAttendanceRouter, type AttendanceOperations } from './routes/attendance';

export function createApp(
  dependencies: MeRouteDependencies & {
    employees?: EmployeeOperations;
    branches?: BranchOperations;
    attendance?: AttendanceOperations;
  },
) {
  const app = express();

  app.use(cors());
  app.use(express.json());

  app.use('/health', healthRouter);
  app.use('/me', createMeRouter(dependencies));
  if (dependencies.employees) {
    app.use(
      '/employees',
      createEmployeesRouter({
        verifyIdToken: dependencies.verifyIdToken,
        employees: dependencies.employees,
      }),
    );
  }
  if (dependencies.branches) {
    app.use(
      '/branches',
      createBranchesRouter({
        verifyIdToken: dependencies.verifyIdToken,
        branches: dependencies.branches,
      }),
    );
  }
  if (dependencies.attendance) {
    app.use(
      '/attendance',
      createAttendanceRouter({
        verifyIdToken: dependencies.verifyIdToken,
        attendance: dependencies.attendance,
      }),
    );
  }

  app.use((_req, _res, next) => {
    next(new AppError(404, 'NOT_FOUND', 'Not found.'));
  });
  app.use(errorHandler);

  return app;
}
