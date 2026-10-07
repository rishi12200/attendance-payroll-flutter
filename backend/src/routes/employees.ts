import { Router } from 'express';
import type { IdTokenVerifier } from '../middleware/auth';
import { createAuthMiddleware, requireRole } from '../middleware/auth';
import { validate } from '../middleware/validate';
import { serialize } from '../services/serialize';
import {
  toEmployeeDto,
  type EmployeeRecord,
  type SalaryRevision,
} from '../services/employee-service';
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
  const getAdminEmployee = (uid: string, callerUid: string) =>
    dependencies.employees.getEmployee(uid, { uid: callerUid, role: 'admin' });

  router.post(
    '/',
    authenticate,
    admin,
    validate(createEmployeeSchema),
    async (req, res) => {
      const created = await dependencies.employees.createEmployee(
        res.locals.validatedParts.body,
      );
      if (typeof created.uid !== 'string') {
        throw new Error('Created employee record is missing its uid.');
      }
      const employee = await getAdminEmployee(created.uid, req.user!.uid);
      res.status(201).json(serialize(toEmployeeDto(employee, 'admin')));
    },
  );

  router.get(
    '/',
    authenticate,
    admin,
    validate(listEmployeesQuerySchema, 'query'),
    async (_req, res) => {
      const { status } = res.locals.validatedParts.query;
      res.json(
        serialize(
          (await dependencies.employees.listEmployees(status)).map((employee) =>
            toEmployeeDto(employee, 'admin'),
          ),
        ),
      );
    },
  );

  router.get(
    '/:id/salary',
    authenticate,
    admin,
    validate(employeeIdParamsSchema, 'params'),
    async (_req, res) => {
      const { id } = res.locals.validatedParts.params;
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
      const { id } = res.locals.validatedParts.params;
      const { effectiveFrom, monthlyCtcPaise } = res.locals.validatedParts.body;
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
      const { id } = res.locals.validatedParts.params;
      await dependencies.employees.updateEmployee(
        id,
        res.locals.validatedParts.body,
        req.user!.uid,
      );
      const employee = await getAdminEmployee(id, req.user!.uid);
      res.json(serialize(toEmployeeDto(employee, 'admin')));
    },
  );

  router.post(
    '/:id/deactivate',
    authenticate,
    admin,
    validate(employeeIdParamsSchema, 'params'),
    validate(deactivateEmployeeSchema),
    async (req, res) => {
      const { id } = res.locals.validatedParts.params;
      const { dol } = res.locals.validatedParts.body;
      await dependencies.employees.deactivateEmployee(id, req.user!.uid, dol);
      const employee = await getAdminEmployee(id, req.user!.uid);
      res.json(serialize(toEmployeeDto(employee, 'admin')));
    },
  );

  router.post(
    '/:id/reactivate',
    authenticate,
    admin,
    validate(employeeIdParamsSchema, 'params'),
    async (req, res) => {
      const { id } = res.locals.validatedParts.params;
      await dependencies.employees.reactivateEmployee(id, req.user!.uid);
      const employee = await getAdminEmployee(id, req.user!.uid);
      res.json(serialize(toEmployeeDto(employee, 'admin')));
    },
  );

  router.get(
    '/:id',
    authenticate,
    signedIn,
    validate(employeeIdParamsSchema, 'params'),
    async (req, res) => {
      const { id } = res.locals.validatedParts.params;
      res.json(
        serialize(
          toEmployeeDto(
            await dependencies.employees.getEmployee(id, {
              uid: req.user!.uid,
              role: req.user!.role,
            }),
            req.user!.role === 'employee' ? 'employee' : 'admin',
          ),
        ),
      );
    },
  );

  return router;
}
