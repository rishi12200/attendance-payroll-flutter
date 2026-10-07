import { AppError } from '../errors/app-error';
import type { EmployeeRecord } from './employee-service';

export type BranchStatus = 'active' | 'inactive';

export interface BranchRecord extends Record<string, unknown> {
  id: string;
  name: string;
  state: string;
  lat: number;
  lng: number;
  radiusMeters: number;
  status: BranchStatus;
}

export interface BranchStore {
  serverTimestamp(): unknown;
  listBranches(): Promise<BranchRecord[]>;
  getBranch(id: string): Promise<BranchRecord | undefined>;
  createBranch(branch: Record<string, unknown>): Promise<string>;
  updateBranch(id: string, values: Record<string, unknown>): Promise<void>;
}

export interface BranchEmployeeStore {
  listEmployees(): Promise<EmployeeRecord[]>;
  getEmployee(uid: string): Promise<EmployeeRecord | undefined>;
}

export interface BranchInput {
  name: string;
  address?: string;
  state: string;
  lat: number;
  lng: number;
  radiusMeters: number;
}

export interface EmployeeBranchAssignment {
  primaryBranchId?: string | null;
  allowedBranchIds?: string[];
}

export function toBranchDto(branch: BranchRecord): BranchRecord {
  return { ...branch };
}

export class BranchService {
  constructor(
    private readonly branches: BranchStore,
    private readonly employees: BranchEmployeeStore,
  ) {}

  async createBranch(input: BranchInput): Promise<BranchRecord> {
    const duplicate = (await this.branches.listBranches()).find(
      (branch) =>
        branch.status === 'active' &&
        branch.name.trim().toLocaleLowerCase() ===
          input.name.trim().toLocaleLowerCase(),
    );
    if (duplicate) {
      throw new AppError(
        409,
        'BRANCH_NAME_EXISTS',
        'An active branch already uses this name.',
        { branchId: duplicate.id },
      );
    }

    const timestamp = this.branches.serverTimestamp();
    const id = await this.branches.createBranch({
      ...input,
      address: input.address ?? '',
      status: 'active',
      createdAt: timestamp,
      updatedAt: timestamp,
    });
    return this.requireBranch(id);
  }

  async listBranches(
    caller: { uid: string; role: string },
    status: BranchStatus | 'all' = 'active',
  ): Promise<BranchRecord[]> {
    const branches = await this.branches.listBranches();
    if (caller.role === 'admin') {
      return branches
        .filter((branch) => status === 'all' || branch.status === status)
        .map(toBranchDto);
    }

    const employee = await this.employees.getEmployee(caller.uid);
    if (!employee) {
      throw new AppError(404, 'EMPLOYEE_NOT_FOUND', 'Employee was not found.');
    }
    const allowedBranchIds = Array.isArray(employee.allowedBranchIds)
      ? employee.allowedBranchIds.filter((id): id is string => typeof id === 'string')
      : [];
    const allowed = new Set(allowedBranchIds);
    return branches
      .filter((branch) => branch.status === 'active' && allowed.has(branch.id))
      .map(toBranchDto);
  }

  async getBranch(
    id: string,
    caller: { uid: string; role: string },
  ): Promise<BranchRecord> {
    const branch = await this.requireBranch(id);
    if (caller.role === 'admin') return toBranchDto(branch);

    const employee = await this.employees.getEmployee(caller.uid);
    if (!employee) {
      throw new AppError(404, 'EMPLOYEE_NOT_FOUND', 'Employee was not found.');
    }
    const allowedBranchIds = Array.isArray(employee.allowedBranchIds)
      ? employee.allowedBranchIds
      : [];
    if (branch.status !== 'active' || !allowedBranchIds.includes(id)) {
      throw new AppError(
        403,
        'FORBIDDEN',
        'Employees may only access their active assigned branches.',
      );
    }
    return toBranchDto(branch);
  }

  async updateBranch(
    id: string,
    changes: Partial<BranchInput>,
    editedBy: string,
  ): Promise<BranchRecord> {
    const existing = await this.requireBranch(id);
    const newName = changes.name?.trim();
    if (newName && existing.status === 'active') {
      const duplicate = (await this.branches.listBranches()).find(
        (branch) =>
          branch.id !== id &&
          branch.status === 'active' &&
          branch.name.trim().toLocaleLowerCase() === newName.toLocaleLowerCase(),
      );
      if (duplicate) {
        throw new AppError(
          409,
          'BRANCH_NAME_EXISTS',
          'An active branch already uses this name.',
          { branchId: duplicate.id },
        );
      }
    }

    await this.branches.updateBranch(id, {
      ...changes,
      updatedAt: this.branches.serverTimestamp(),
      editedBy,
    });
    return this.requireBranch(id);
  }

  async deactivateBranch(id: string): Promise<BranchRecord> {
    const branch = await this.requireBranch(id);
    if (branch.status === 'inactive') return toBranchDto(branch);

    const employees = await this.employees.listEmployees();
    const assignedEmployees = employees.filter((employee) => {
      if (employee.role !== 'employee' || employee.status !== 'active') return false;
      const allowedBranchIds = Array.isArray(employee.allowedBranchIds)
        ? employee.allowedBranchIds
        : [];
      return (
        employee.primaryBranchId === id ||
        allowedBranchIds.includes(id)
      );
    });
    if (assignedEmployees.length > 0) {
      throw new AppError(
        409,
        'BRANCH_HAS_ACTIVE_EMPLOYEES',
        `Cannot deactivate this branch while ${assignedEmployees.length} active employee(s) are assigned to it.`,
        { activeEmployeeCount: assignedEmployees.length },
      );
    }

    await this.branches.updateBranch(id, {
      status: 'inactive',
      updatedAt: this.branches.serverTimestamp(),
    });
    return this.requireBranch(id);
  }

  async reactivateBranch(id: string): Promise<BranchRecord> {
    const branch = await this.requireBranch(id);
    if (branch.status === 'active') return toBranchDto(branch);

    const duplicate = (await this.branches.listBranches()).find(
      (candidate) =>
        candidate.id !== id &&
        candidate.status === 'active' &&
        candidate.name.trim().toLocaleLowerCase() ===
          branch.name.trim().toLocaleLowerCase(),
    );
    if (duplicate) {
      throw new AppError(
        409,
        'BRANCH_NAME_EXISTS',
        'An active branch already uses this name.',
        { branchId: duplicate.id },
      );
    }

    await this.branches.updateBranch(id, {
      status: 'active',
      updatedAt: this.branches.serverTimestamp(),
    });
    return this.requireBranch(id);
  }

  private async requireBranch(id: string): Promise<BranchRecord> {
    const branch = await this.branches.getBranch(id);
    if (!branch) throw new AppError(404, 'BRANCH_NOT_FOUND', 'Branch was not found.');
    return { ...branch, id };
  }
}

export function normalizeEmployeeAssignment(
  current: EmployeeRecord | undefined,
  changes: EmployeeBranchAssignment,
): { primaryBranchId: string | null; allowedBranchIds: string[] } {
  const primaryBranchId =
    changes.primaryBranchId !== undefined
      ? typeof changes.primaryBranchId === 'string'
        ? changes.primaryBranchId.trim()
        : changes.primaryBranchId
      : current?.primaryBranchId ?? null;
  const allowedBranchIds =
    changes.allowedBranchIds !== undefined
      ? changes.allowedBranchIds.map((id) => id.trim())
      : Array.isArray(current?.allowedBranchIds)
        ? current.allowedBranchIds.map((id) => id.trim())
        : [];
  if (
    (primaryBranchId !== null &&
      (typeof primaryBranchId !== 'string' || primaryBranchId.length === 0)) ||
    allowedBranchIds.some((id) => id.length === 0)
  ) {
    throw new AppError(
      422,
      'INVALID_BRANCH_ASSIGNMENT',
      'Branch IDs must be non-empty strings or null for the primary branch.',
    );
  }
  if (new Set(allowedBranchIds).size !== allowedBranchIds.length) {
    throw new AppError(
      422,
      'DUPLICATE_BRANCH_ASSIGNMENT',
      'Allowed branch IDs must not contain duplicates.',
    );
  }
  if (primaryBranchId !== null && !allowedBranchIds.includes(primaryBranchId)) {
    allowedBranchIds.push(primaryBranchId);
  }
  if (allowedBranchIds.length > 20) {
    throw new AppError(
      422,
      'TOO_MANY_BRANCH_ASSIGNMENTS',
      'An employee may be assigned to at most 20 branches.',
    );
  }
  return { primaryBranchId, allowedBranchIds };
}

export async function validateEmployeeAssignment(
  assignment: { primaryBranchId: string | null; allowedBranchIds: string[] },
  branches: BranchStore,
): Promise<void> {
  const ids = new Set(assignment.allowedBranchIds);
  if (assignment.primaryBranchId !== null) ids.add(assignment.primaryBranchId);

  for (const id of ids) {
    const branch = await branches.getBranch(id);
    if (!branch || branch.status !== 'active') {
      throw new AppError(
        422,
        'BRANCH_NOT_ASSIGNABLE',
        `Branch "${id}" does not exist or is inactive.`,
        { branchId: id },
      );
    }
  }
}
