import { AppError } from '../errors/app-error';

export type LeaveTypeStatus = 'active' | 'inactive';

export interface LeaveTypeRecord extends Record<string, unknown> {
  id: string;
  name: string;
  code: string;
  paid: boolean;
  annualQuotaDays: number | null;
  allowHalfDay: boolean;
  status: LeaveTypeStatus;
  system: boolean;
  sortOrder: number;
  createdAt?: unknown;
  updatedAt?: unknown;
  editedBy?: string;
}

export interface LeaveTypeStore {
  serverTimestamp(): unknown;
  listLeaveTypes(): Promise<LeaveTypeRecord[]>;
  getLeaveType(id: string): Promise<LeaveTypeRecord | undefined>;
  writeLeaveType(input: {
    id: string;
    before?: LeaveTypeRecord;
    after: LeaveTypeRecord;
    action: 'leaveType.create' | 'leaveType.update' | 'leaveType.deactivate' | 'leaveType.reactivate';
    by: string;
    createOnly: boolean;
  }): Promise<void>;
  countPendingRequests(leaveTypeId: string): Promise<number>;
}

export type LeaveTypePatch = Partial<Pick<LeaveTypeRecord,
  'name' | 'code' | 'paid' | 'annualQuotaDays' | 'allowHalfDay' | 'sortOrder'
>>;

export function toLeaveTypeDto(type: LeaveTypeRecord, admin = true): Record<string, unknown> {
  if (admin) return { ...type };
  return {
    id: type.id,
    name: type.name,
    code: type.code,
    paid: type.paid,
    allowHalfDay: type.allowHalfDay,
    annualQuotaDays: type.annualQuotaDays,
  };
}

export class LeaveTypeService {
  constructor(private readonly store: LeaveTypeStore) {}

  async list(caller: { role: string }, status: LeaveTypeStatus | 'all' = 'all') {
    const admin = caller.role === 'admin';
    if (!admin && caller.role !== 'employee') throw forbidden();
    const types = (await this.store.listLeaveTypes())
      .filter((type) => admin
        ? status === 'all' || type.status === status
        : type.status === 'active' && type.id !== 'legacy-paid')
      .sort((left, right) => left.sortOrder - right.sortOrder || left.name.localeCompare(right.name));
    return types.map((type) => toLeaveTypeDto(type, admin));
  }

  async create(input: LeaveTypePatch, by: string): Promise<Record<string, unknown>> {
    const all = await this.store.listLeaveTypes();
    assertUnique(all, input.name!, input.code!);
    const timestamp = this.store.serverTimestamp();
    const type: LeaveTypeRecord = {
      id: '', ...input,
      status: 'active', system: false,
      sortOrder: input.sortOrder ?? (all.reduce((max, item) => Math.max(max, item.sortOrder), -1) + 1),
      createdAt: timestamp, updatedAt: timestamp, editedBy: by,
    } as LeaveTypeRecord;
    const id = `custom-${crypto.randomUUID()}`;
    type.id = id;
    await this.store.writeLeaveType({
      id, after: type, action: 'leaveType.create', by, createOnly: true,
    });
    return toLeaveTypeDto((await this.requireType(id)));
  }

  async update(id: string, changes: LeaveTypePatch, by: string): Promise<Record<string, unknown>> {
    const before = await this.requireType(id);
    if (id === 'unpaid' && (
      changes.paid !== undefined && changes.paid !== before.paid ||
      changes.annualQuotaDays !== undefined && changes.annualQuotaDays !== before.annualQuotaDays
    )) {
      throw new AppError(422, 'SYSTEM_LEAVE_TYPE', 'The unpaid system type cannot change paid or annualQuotaDays.');
    }
    if (id === 'legacy-paid' && (
      changes.paid !== undefined && changes.paid !== before.paid ||
      changes.annualQuotaDays !== undefined && changes.annualQuotaDays !== before.annualQuotaDays
    )) {
      throw new AppError(422, 'SYSTEM_LEAVE_TYPE', 'The legacy paid system type cannot change paid or annualQuotaDays.');
    }
    const all = await this.store.listLeaveTypes();
    assertUnique(all.filter((type) => type.id !== id), changes.name ?? before.name, changes.code ?? before.code);
    const after = {
      ...before, ...changes, updatedAt: this.store.serverTimestamp(), editedBy: by,
    };
    await this.store.writeLeaveType({
      id, before, after, action: 'leaveType.update', by, createOnly: false,
    });
    return toLeaveTypeDto(await this.requireType(id));
  }

  async deactivate(id: string, by: string): Promise<Record<string, unknown>> {
    const before = await this.requireType(id);
    if (id === 'unpaid') throw new AppError(422, 'SYSTEM_LEAVE_TYPE', 'The unpaid system type cannot be deactivated.');
    if (before.status === 'inactive') return toLeaveTypeDto(before);
    const count = await this.store.countPendingRequests(id);
    if (count > 0) {
      throw new AppError(409, 'LEAVE_TYPE_IN_USE', `Cannot deactivate this leave type while ${count} pending request(s) use it.`, { pendingCount: count });
    }
    const after = { ...before, status: 'inactive' as const, updatedAt: this.store.serverTimestamp(), editedBy: by };
    await this.store.writeLeaveType({ id, before, after, action: 'leaveType.deactivate', by, createOnly: false });
    return toLeaveTypeDto(await this.requireType(id));
  }

  async reactivate(id: string, by: string): Promise<Record<string, unknown>> {
    const before = await this.requireType(id);
    if (id === 'legacy-paid') throw new AppError(422, 'SYSTEM_LEAVE_TYPE', 'The legacy paid system type can never be activated.');
    if (before.status === 'active') return toLeaveTypeDto(before);
    const after = { ...before, status: 'active' as const, updatedAt: this.store.serverTimestamp(), editedBy: by };
    await this.store.writeLeaveType({ id, before, after, action: 'leaveType.reactivate', by, createOnly: false });
    return toLeaveTypeDto(await this.requireType(id));
  }

  private async requireType(id: string): Promise<LeaveTypeRecord> {
    const type = await this.store.getLeaveType(id);
    if (!type) throw new AppError(404, 'LEAVE_TYPE_NOT_FOUND', 'Leave type was not found.');
    return type;
  }
}

function assertUnique(types: LeaveTypeRecord[], name: string, code: string): void {
  const normalizedName = name.trim().toLocaleLowerCase();
  if (types.some((type) => type.name.trim().toLocaleLowerCase() === normalizedName)) {
    throw new AppError(409, 'LEAVE_TYPE_NAME_EXISTS', 'A leave type already uses this name.');
  }
  const normalizedCode = code.toUpperCase();
  if (types.some((type) => type.code.toUpperCase() === normalizedCode)) {
    throw new AppError(409, 'LEAVE_TYPE_CODE_EXISTS', 'A leave type already uses this code.');
  }
}

function forbidden(): AppError {
  return new AppError(403, 'FORBIDDEN', 'You do not have permission to access this resource.');
}
