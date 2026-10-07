import { AppError } from '../errors/app-error';
import { compareDateStrings, isDateBefore, todayIST } from '../domain/dates';
import { formatEmpCode } from '../domain/emp-code';

export type EmployeeStatus = 'active' | 'inactive';
export type EmployeeRole = 'admin' | 'employee';
export type EmployeeRecord = Record<string, unknown> & {
  role: EmployeeRole;
  status: EmployeeStatus;
  doj?: string;
  dol?: string | null;
};

export interface SalaryRevision {
  empId: string;
  effectiveFrom: string;
  monthlyCtcPaise: number;
  [key: string]: unknown;
}

export interface CreateEmployeeInput {
  name: string;
  email: string;
  tempPassword: string;
  phone?: string;
  designation?: string;
  doj: string;
  monthlyCtcPaise: number;
}

export interface EmployeeAuth {
  createUser(input: { email: string; password: string }): Promise<{ uid: string }>;
  setCustomUserClaims(uid: string, claims: Record<string, string>): Promise<void>;
  deleteUser(uid: string): Promise<void>;
  getUser(uid: string): Promise<{ disabled: boolean; customClaims?: Record<string, unknown> }>;
  updateUser(uid: string, properties: { disabled: boolean }): Promise<unknown>;
  revokeRefreshTokens(uid: string): Promise<void>;
}

export interface EmployeeTransaction {
  getCounter(): Promise<number>;
  getEmployee(uid: string): Promise<EmployeeRecord | undefined>;
  getSalaryRevision(id: string): Promise<SalaryRevision | undefined>;
  setCounter(value: number): void;
  createEmployee(uid: string, employee: Record<string, unknown>): void;
  createSalaryRevision(id: string, revision: SalaryRevision): void;
}

export interface EmployeeStore {
  serverTimestamp(): unknown;
  runTransaction<T>(work: (transaction: EmployeeTransaction) => Promise<T>): Promise<T>;
  listEmployees(): Promise<EmployeeRecord[]>;
  getEmployee(uid: string): Promise<EmployeeRecord | undefined>;
  getSalaryHistory(uid: string): Promise<SalaryRevision[]>;
  updateEmployee(uid: string, values: Record<string, unknown>): Promise<void>;
  getSalaryRevision(id: string): Promise<SalaryRevision | undefined>;
}

export interface EmployeeServiceDependencies {
  auth: EmployeeAuth;
  store: EmployeeStore;
  today?: () => string;
}

export class EmployeeService {
  private readonly auth: EmployeeAuth;
  private readonly store: EmployeeStore;
  private readonly today: () => string;

  constructor(dependencies: EmployeeServiceDependencies) {
    this.auth = dependencies.auth;
    this.store = dependencies.store;
    this.today = dependencies.today ?? todayIST;
  }

  async createEmployee(input: CreateEmployeeInput): Promise<EmployeeRecord> {
    let uid: string;
    try {
      ({ uid } = await this.auth.createUser({
        email: input.email,
        password: input.tempPassword,
      }));
    } catch (error) {
      if (firebaseCode(error) === 'auth/email-already-exists') {
        throw new AppError(409, 'EMAIL_ALREADY_EXISTS', 'An account already uses this email.');
      }
      throw error;
    }

    try {
      await this.auth.setCustomUserClaims(uid, { role: 'employee' });
      const employee = await this.store.runTransaction(async (transaction) => {
        const nextSequence = (await transaction.getCounter()) + 1;
        const existingEmployee = await transaction.getEmployee(uid);
        const salaryId = `${uid}_${input.doj}`;
        const existingSalary = await transaction.getSalaryRevision(salaryId);

        if (existingEmployee) {
          throw new AppError(409, 'EMPLOYEE_ALREADY_EXISTS', 'An employee profile already exists.');
        }
        if (existingSalary) {
          throw new AppError(409, 'SALARY_REVISION_EXISTS', 'The initial salary revision already exists.');
        }

        const timestamp = this.store.serverTimestamp();
        const employeeRecord: EmployeeRecord = {
          empCode: formatEmpCode(nextSequence),
          name: input.name,
          email: input.email,
          role: 'employee',
          status: 'active',
          doj: input.doj,
          createdAt: timestamp,
          updatedAt: timestamp,
        };
        if (input.phone !== undefined) employeeRecord.phone = input.phone;
        if (input.designation !== undefined) employeeRecord.designation = input.designation;

        transaction.setCounter(nextSequence);
        transaction.createEmployee(uid, employeeRecord);
        transaction.createSalaryRevision(salaryId, {
          empId: uid,
          effectiveFrom: input.doj,
          monthlyCtcPaise: input.monthlyCtcPaise,
        });
        return employeeRecord;
      });
      return { ...employee, uid };
    } catch (error) {
      try {
        await this.auth.deleteUser(uid);
      } catch (cleanupError) {
        throw new AppError(
          500,
          'EMPLOYEE_ROLLBACK_FAILED',
          `Employee setup failed and the temporary Auth account (${uid}) could not be removed.`,
          { cleanupCode: firebaseCode(cleanupError) ?? 'UNKNOWN' },
        );
      }
      if (error instanceof AppError) throw error;
      throw new AppError(
        500,
        'EMPLOYEE_CREATE_FAILED',
        `Employee setup failed. The temporary Auth account (${uid}) was removed.`,
      );
    }
  }

  async listEmployees(status: 'active' | 'inactive' | 'all' = 'active') {
    const employees = await this.store.listEmployees();
    return employees
      .filter((employee) => employee.role === 'employee')
      .filter((employee) => status === 'all' || employee.status === status)
      .sort((left, right) => String(left.empCode ?? '').localeCompare(String(right.empCode ?? '')))
      .map(({ currentMonthlyCtcPaise: _currentSalary, monthlyCtcPaise: _salary, ...employee }) => employee);
  }

  async getEmployee(
    uid: string,
    caller: { uid: string; role: string },
  ): Promise<EmployeeRecord> {
    if (caller.role !== 'admin' && caller.uid !== uid) {
      throw new AppError(403, 'FORBIDDEN', 'Employees may only access their own profile.');
    }

    const employee = await this.requireEmployee(uid);
    const result: EmployeeRecord = { ...employee, uid };
    if (caller.role === 'admin') {
      const today = this.today();
      const revisions = await this.store.getSalaryHistory(uid);
      const current = revisions
        .filter((revision) => compareDateStrings(revision.effectiveFrom, today) <= 0)
        .sort((left, right) => compareDateStrings(right.effectiveFrom, left.effectiveFrom))[0];
      result.currentMonthlyCtcPaise = current?.monthlyCtcPaise;
    } else {
      delete result.currentMonthlyCtcPaise;
    }
    return result;
  }

  async updateEmployee(
    uid: string,
    changes: Record<string, unknown>,
    editedBy: string,
  ): Promise<EmployeeRecord> {
    const existing = await this.requireEmployee(uid);
    if (existing.role === 'admin') {
      throw new AppError(403, 'ADMIN_PROFILE_PROTECTED', 'Admin profiles cannot be edited here.');
    }
    const values = {
      ...changes,
      updatedAt: this.store.serverTimestamp(),
      editedBy,
      editedAt: this.store.serverTimestamp(),
    };
    await this.store.updateEmployee(uid, values);
    return { ...existing, ...values, uid };
  }

  async addSalaryRevision(
    uid: string,
    effectiveFrom: string,
    monthlyCtcPaise: number,
  ): Promise<SalaryRevision> {
    const employee = await this.requireEmployee(uid);
    if (employee.role !== 'employee') {
      throw new AppError(422, 'INVALID_EMPLOYEE_ROLE', 'Salary revisions are only allowed for employees.');
    }
    if (employee.doj && isDateBefore(effectiveFrom, employee.doj)) {
      throw new AppError(422, 'INVALID_EFFECTIVE_DATE', 'Salary effective date cannot be before the date of joining.');
    }

    const salaryId = `${uid}_${effectiveFrom}`;
    return this.store.runTransaction(async (transaction) => {
      const revision = await transaction.getSalaryRevision(salaryId);
      if (revision) {
        throw new AppError(409, 'SALARY_REVISION_EXISTS', 'A salary revision already exists for this date.');
      }
      const record: SalaryRevision = { empId: uid, effectiveFrom, monthlyCtcPaise };
      transaction.createSalaryRevision(salaryId, record);
      return record;
    });
  }

  async listSalaryHistory(uid: string): Promise<SalaryRevision[]> {
    await this.requireEmployee(uid);
    return (await this.store.getSalaryHistory(uid)).sort((left, right) =>
      compareDateStrings(right.effectiveFrom, left.effectiveFrom),
    );
  }

  async deactivateEmployee(
    uid: string,
    callerUid: string,
    dol?: string,
  ): Promise<EmployeeRecord> {
    const employee = await this.requireEmployee(uid);
    if (employee.role === 'admin') {
      throw new AppError(403, 'ADMIN_DEACTIVATION_FORBIDDEN', 'Admin accounts cannot be deactivated here.');
    }
    if (uid === callerUid) {
      throw new AppError(403, 'SELF_DEACTIVATION_FORBIDDEN', 'You cannot deactivate your own account.');
    }

    const lastDay = dol ?? this.today();
    if (employee.doj && isDateBefore(lastDay, employee.doj)) {
      throw new AppError(422, 'INVALID_DOL', 'Date of leaving cannot be before the date of joining.');
    }
    if (employee.status === 'inactive') return { ...employee, uid };

    try {
      await this.auth.updateUser(uid, { disabled: true });
      await this.auth.revokeRefreshTokens(uid);
    } catch (error) {
      throw new AppError(
        500,
        'AUTH_DEACTIVATION_FAILED',
        `Could not disable Auth access for employee ${uid}.`,
        { firebaseCode: firebaseCode(error) ?? 'UNKNOWN' },
      );
    }

    const values: Record<string, unknown> = {
      status: 'inactive' as const,
      dol: lastDay,
      updatedAt: this.store.serverTimestamp(),
      editedBy: callerUid,
      editedAt: this.store.serverTimestamp(),
    };
    try {
      await this.store.updateEmployee(uid, values);
    } catch {
      throw new AppError(
        500,
        'EMPLOYEE_DEACTIVATION_PARTIAL',
        `Auth access is disabled for employee ${uid}, but the profile update failed.`,
      );
    }
    return { ...employee, ...values, uid };
  }

  async reactivateEmployee(uid: string, callerUid: string): Promise<EmployeeRecord> {
    const employee = await this.requireEmployee(uid);
    try {
      await this.auth.updateUser(uid, { disabled: false });
    } catch (error) {
      throw new AppError(
        500,
        'AUTH_REACTIVATION_FAILED',
        `Could not enable Auth access for employee ${uid}.`,
        { firebaseCode: firebaseCode(error) ?? 'UNKNOWN' },
      );
    }

    const values: Record<string, unknown> = {
      status: 'active' as const,
      dol: null,
      updatedAt: this.store.serverTimestamp(),
      editedBy: callerUid,
      editedAt: this.store.serverTimestamp(),
    };
    await this.store.updateEmployee(uid, values);
    return { ...employee, ...values, uid, status: 'active' };
  }

  private async requireEmployee(uid: string): Promise<EmployeeRecord> {
    const employee = await this.store.getEmployee(uid);
    if (!employee) throw new AppError(404, 'EMPLOYEE_NOT_FOUND', 'Employee was not found.');
    return employee;
  }
}

function firebaseCode(error: unknown): string | undefined {
  if (
    typeof error === 'object' &&
    error !== null &&
    'code' in error &&
    typeof error.code === 'string'
  ) {
    return error.code;
  }
  return undefined;
}
