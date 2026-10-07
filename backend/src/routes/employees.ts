import { Router } from 'express';
import type { IdTokenVerifier } from '../middleware/auth';
import { createAuthMiddleware, requireRole } from '../middleware/auth';
import { validate } from '../middleware/validate';
import { serialize } from '../services/serialize';
import type { EmployeeRecord, SalaryRevision } from '../services/employee-service';
import {
  createEmployeeSchema,
  deactivateEmployeeSchema,
  employeeIdParamsSchema,
  listEmployeesQuerySchema,
  patchEmployeeSchema,
  salaryRevisionSchema,
} from './employee-schemas';

export interface EmployeeOperations {
  createEmployee(input: {
    name: string;
    email: string;
    tempPassword: string;
    phone?: string;
    designation?: string;
    doj: string;
    monthlyCtcPaise: number;
  }): Promise<EmployeeRecord>;
  listEmployees(status: 'active' | 'inactive' | 'all'): Promise<EmployeeRecord[]>;
  getEmployee(uid: string, caller: { uid: string; role: string }): Promise<EmployeeRecord>;
  updateEmployee(
    uid: string,
    changes: Record<string, unknown>,
    editedBy: string,
  ): Promise<EmployeeRecord>;
  addSalaryRevision(
    uid: string,
    effectiveFrom: string,
    monthlyCtcPaise: number,
  ): Promise<SalaryRevision>;
  listSalaryHistory(uid: string): Promise<SalaryRevision[]>;
  deactivateEmployee(uid: string, callerUid: string, dol?: string): Promise<EmployeeRecord>;
  reactivateEmployee(uid: string, callerUid: string): Promise<EmployeeRecord>;
}

export interface EmployeesRouteDependencies {
  verifyIdToken: IdTokenVerifier;
  employees: EmployeeOperations;
}

export function createEmployeesRouter(dependencies: EmployeesRouteDependencies) {
  const router = Router();
  const authenticate = createAuthMiddleware(dependencies.verifyIdToken);
  const admin = requireRole('admin');
  const signedIn = requireRole('admin', 'employee');

  router.post(
    '/',
    authenticate,
    admin,
    validate(createEmployeeSchema),
    async (_req, res) => {
      const employee = await dependencies.employees.createEmployee(res.locals.validated);
      res.status(201).json(serialize(employee));
    },
  );

  router.get(
    '/',
    authenticate,
    admin,
    validate(listEmployeesQuerySchema, 'query'),
    async (_req, res) => {
      const { status } = res.locals.validated;
      res.json(serialize(await dependencies.employees.listEmployees(status)));
    },
  );

  router.get(
    '/:id/salary',
    authenticate,
    admin,
    validate(employeeIdParamsSchema, 'params'),
    async (_req, res) => {
      const { id } = res.locals.validated;
      res.json(serialize(await dependencies.employees.listSalaryHistory(id)));
    },
  );

  router.post(
    '/:id/salary',
    authenticate,
    admin,
    validate(employeeIdParamsSchema, 'params'),
    validate(salaryRevisionSchema),
    async (_req, res) => {
      const { id } = res.locals.validated;
      const { effectiveFrom, monthlyCtcPaise } = res.locals.validated;
      res
        .status(201)
        .json(
          serialize(
            await dependencies.employees.addSalaryRevision(
              id,
              effectiveFrom,
              monthlyCtcPaise,
            ),
          ),
        );
    },
  );

  router.patch(
    '/:id',
    authenticate,
    admin,
    validate(employeeIdParamsSchema, 'params'),
    validate(patchEmployeeSchema),
    async (req, res) => {
      const { id } = res.locals.validated;
      const employee = await dependencies.employees.updateEmployee(
        id,
        res.locals.validated,
        req.user!.uid,
      );
      res.json(serialize(employee));
    },
  );

  router.post(
    '/:id/deactivate',
    authenticate,
    admin,
    validate(employeeIdParamsSchema, 'params'),
    validate(deactivateEmployeeSchema),
    async (req, res) => {
      const { id } = res.locals.validated;
      const { dol } = res.locals.validated;
      res.json(
        serialize(
          await dependencies.employees.deactivateEmployee(id, req.user!.uid, dol),
        ),
      );
    },
  );

  router.post(
    '/:id/reactivate',
    authenticate,
    admin,
    validate(employeeIdParamsSchema, 'params'),
    async (req, res) => {
      const { id } = res.locals.validated;
      res.json(
        serialize(await dependencies.employees.reactivateEmployee(id, req.user!.uid)),
      );
    },
  );

  router.get(
    '/:id',
    authenticate,
    signedIn,
    validate(employeeIdParamsSchema, 'params'),
    async (req, res) => {
      const { id } = res.locals.validated;
      res.json(
        serialize(
          await dependencies.employees.getEmployee(id, {
            uid: req.user!.uid,
            role: req.user!.role,
          }),
        ),
      );
    },
  );

  return router;
}
