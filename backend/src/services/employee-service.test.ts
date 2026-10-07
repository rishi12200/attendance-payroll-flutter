import assert from 'node:assert/strict';
import test from 'node:test';
import { AppError } from '../errors/app-error';
import type {
  EmployeeAuth,
  EmployeeRecord,
  EmployeeStore,
  EmployeeTransaction,
  SalaryRevision,
} from './employee-service';
import { EmployeeService } from './employee-service';

class FakeEmployeeAuth implements EmployeeAuth {
  readonly accounts = new Map<
    string,
    { email: string; password: string; disabled: boolean; claims: Record<string, string> }
  >();
  readonly events: string[] = [];
  private nextUid = 1;

  async createUser(input: { email: string; password: string }) {
    if ([...this.accounts.values()].some((account) => account.email === input.email)) {
      throw Object.assign(new Error('duplicate'), { code: 'auth/email-already-exists' });
    }
    const uid = `uid-${this.nextUid++}`;
    this.events.push(`create:${uid}`);
    this.accounts.set(uid, {
      email: input.email,
      password: input.password,
      disabled: false,
      claims: {},
    });
    return { uid };
  }

  async setCustomUserClaims(uid: string, claims: Record<string, string>) {
    this.events.push(`claims:${uid}:${claims.role}`);
    this.accounts.get(uid)!.claims = claims;
  }

  async deleteUser(uid: string) {
    this.events.push(`delete:${uid}`);
    this.accounts.delete(uid);
  }

  async getUser(uid: string) {
    const account = this.accounts.get(uid);
    if (!account) throw new Error('missing user');
    return { disabled: account.disabled, customClaims: account.claims };
  }

  async updateUser(uid: string, properties: { disabled: boolean }) {
    this.events.push(`disabled:${uid}:${properties.disabled}`);
    this.accounts.get(uid)!.disabled = properties.disabled;
    return {};
  }

  async revokeRefreshTokens(uid: string) {
    this.events.push(`revoke:${uid}`);
  }
}

class FakeEmployeeStore implements EmployeeStore {
  counter = 0;
  readonly employees = new Map<string, EmployeeRecord>();
  readonly salaries = new Map<string, SalaryRevision>();
  failTransaction = false;
  failEmployeeUpdate = false;
  readonly events: string[] = [];
  private sequence = 0;

  serverTimestamp() {
    return `server-time-${++this.sequence}`;
  }

  async runTransaction<T>(work: (transaction: EmployeeTransaction) => Promise<T>): Promise<T> {
    const pending: Array<() => void> = [];
    const tx: EmployeeTransaction = {
      getCounter: async () => this.counter,
      getEmployee: async (uid) => this.employees.get(uid),
      getSalaryRevision: async (id) => this.salaries.get(id),
      setCounter: (value) => pending.push(() => { this.counter = value; }),
      createEmployee: (uid, employee) =>
        pending.push(() => {
          if (this.employees.has(uid)) throw new Error('employee exists');
          this.employees.set(uid, employee as EmployeeRecord);
        }),
      createSalaryRevision: (id, revision) =>
        pending.push(() => {
          if (this.salaries.has(id)) throw new Error('salary exists');
          this.salaries.set(id, revision);
        }),
    };
    const result = await work(tx);
    if (this.failTransaction) throw new Error('firestore failed');
    for (const commit of pending) commit();
    this.events.push('transaction-committed');
    return result;
  }

  async listEmployees() {
    return [...this.employees.values()];
  }

  async getEmployee(uid: string) {
    return this.employees.get(uid);
  }

  async getSalaryHistory(uid: string) {
    return [...this.salaries.values()].filter((salary) => salary.empId === uid);
  }

  async updateEmployee(uid: string, values: Record<string, unknown>) {
    if (this.failEmployeeUpdate) throw new Error('profile write failed');
    this.events.push(`update:${uid}:${String(values.status ?? 'patch')}`);
    const employee = this.employees.get(uid);
    if (!employee) throw new Error('missing employee');
    this.employees.set(uid, { ...employee, ...values });
  }

  async getSalaryRevision(id: string) {
    return this.salaries.get(id);
  }
}

function employeeService(options: {
  auth?: FakeEmployeeAuth;
  store?: FakeEmployeeStore;
  today?: string;
} = {}) {
  const auth = options.auth ?? new FakeEmployeeAuth();
  const store = options.store ?? new FakeEmployeeStore();
  return {
    auth,
    store,
    service: new EmployeeService({
      auth,
      store,
      today: () => options.today ?? '2026-10-07',
    }),
  };
}

function employeeInput(email = 'worker@example.com') {
  return {
    name: 'Worker',
    email,
    tempPassword: 'temporary-password',
    doj: '2026-10-01',
    monthlyCtcPaise: 2500000,
  };
}

function employeeRecord(
  overrides: Partial<EmployeeRecord> = {},
): EmployeeRecord {
  return {
    empCode: 'EMP001',
    name: 'Worker',
    email: 'worker@example.com',
    role: 'employee',
    status: 'active',
    doj: '2026-10-01',
    ...overrides,
  };
}

async function expectAppError(
  promise: Promise<unknown>,
  status: number,
  code: string,
) {
  await assert.rejects(promise, (error: unknown) => {
    assert.ok(error instanceof AppError);
    assert.equal(error.status, status);
    assert.equal(error.code, code);
    return true;
  });
}

test('creates Auth claim, employee profile, first salary, and never returns password', async () => {
  const { auth, store, service } = employeeService();
  const result = await service.createEmployee(employeeInput());

  assert.equal(result.uid, 'uid-1');
  assert.equal(result.empCode, 'EMP001');
  assert.equal(result.role, 'employee');
  assert.equal(result.status, 'active');
  assert.equal('tempPassword' in result, false);
  assert.deepEqual(auth.accounts.get('uid-1')?.claims, { role: 'employee' });
  assert.deepEqual(store.salaries.get('uid-1_2026-10-01'), {
    empId: 'uid-1',
    effectiveFrom: '2026-10-01',
    monthlyCtcPaise: 2500000,
  });
});

test('maps duplicate Auth email to 409 without exposing credentials', async () => {
  const { service } = employeeService();
  await service.createEmployee(employeeInput());
  await expectAppError(
    service.createEmployee(employeeInput()),
    409,
    'EMAIL_ALREADY_EXISTS',
  );
});

test('removes the Auth user if Firestore transaction fails', async () => {
  const { auth, store, service } = employeeService();
  store.failTransaction = true;
  await expectAppError(
    service.createEmployee(employeeInput()),
    500,
    'EMPLOYEE_CREATE_FAILED',
  );
  assert.equal(auth.accounts.size, 0);
  assert.equal(store.employees.size, 0);
});

test('increments the transaction counter to EMP001 then EMP002', async () => {
  const { service, store } = employeeService();
  const first = await service.createEmployee(employeeInput('one@example.com'));
  const second = await service.createEmployee(employeeInput('two@example.com'));

  assert.equal(first.empCode, 'EMP001');
  assert.equal(second.empCode, 'EMP002');
  assert.equal(store.counter, 2);
});

test('returns 409 for a duplicate salary effective date', async () => {
  const { service } = employeeService();
  const created = await service.createEmployee(employeeInput());
  await expectAppError(
    service.addSalaryRevision(created.uid as string, '2026-10-01', 3000000),
    409,
    'SALARY_REVISION_EXISTS',
  );
});

test('disables then revokes before writing inactive status and DOL', async () => {
  const { auth, store, service } = employeeService();
  const created = await service.createEmployee(employeeInput());
  auth.events.length = 0;
  store.events.length = 0;

  const result = await service.deactivateEmployee(created.uid as string, 'admin-uid');
  assert.deepEqual(auth.events, [
    'disabled:uid-1:true',
    'revoke:uid-1',
  ]);
  assert.deepEqual(store.events, ['update:uid-1:inactive']);
  assert.equal(result.status, 'inactive');
  assert.equal(result.dol, '2026-10-07');
});

test('refuses deactivation of admins and the caller themself', async () => {
  const { store, service } = employeeService();
  store.employees.set('admin-1', employeeRecord({ role: 'admin' }));
  store.employees.set('employee-1', employeeRecord());

  await expectAppError(
    service.deactivateEmployee('admin-1', 'other-admin'),
    403,
    'ADMIN_DEACTIVATION_FORBIDDEN',
  );
  await expectAppError(
    service.deactivateEmployee('employee-1', 'employee-1'),
    403,
    'SELF_DEACTIVATION_FORBIDDEN',
  );
});

test('reactivates the Auth user and clears DOL', async () => {
  const { auth, store, service } = employeeService();
  const created = await service.createEmployee(employeeInput());
  const uid = created.uid as string;
  store.employees.set(uid, {
    ...store.employees.get(uid)!,
    status: 'inactive',
    dol: '2026-10-06',
  });
  auth.accounts.get(uid)!.disabled = true;

  const result = await service.reactivateEmployee(uid, 'admin-uid');

  assert.equal(auth.events.at(-1), `disabled:${uid}:false`);
  assert.equal(result.status, 'active');
  assert.equal(result.dol, null);
});

test('only admins receive current salary and employees can read only themselves', async () => {
  const { store, service } = employeeService();
  store.employees.set('employee-1', employeeRecord());
  store.salaries.set('employee-1_2026-10-01', {
    empId: 'employee-1',
    effectiveFrom: '2026-10-01',
    monthlyCtcPaise: 2500000,
  });
  store.salaries.set('employee-1_2026-10-08', {
    empId: 'employee-1',
    effectiveFrom: '2026-10-08',
    monthlyCtcPaise: 3500000,
  });

  const adminView = await service.getEmployee('employee-1', {
    uid: 'admin-1',
    role: 'admin',
  });
  const ownView = await service.getEmployee('employee-1', {
    uid: 'employee-1',
    role: 'employee',
  });
  assert.equal(adminView.currentMonthlyCtcPaise, 2500000);
  assert.equal('currentMonthlyCtcPaise' in ownView, false);
  await expectAppError(
    service.getEmployee('employee-1', { uid: 'employee-2', role: 'employee' }),
    403,
    'FORBIDDEN',
  );
});
