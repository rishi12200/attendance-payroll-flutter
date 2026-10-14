export interface SeedLeaveType {
  id: string;
  name: string;
  code: string;
  paid: boolean;
  annualQuotaDays: number | null;
  allowHalfDay: boolean;
  status: 'active' | 'inactive';
  system: boolean;
  sortOrder: number;
}

export const defaultLeaveTypes: readonly SeedLeaveType[] = [
  { id: 'annual', name: 'Annual Leave', code: 'AL', paid: true, annualQuotaDays: 18, allowHalfDay: true, status: 'active', system: false, sortOrder: 1 },
  { id: 'casual', name: 'Casual Leave', code: 'CL', paid: true, annualQuotaDays: 8, allowHalfDay: true, status: 'active', system: false, sortOrder: 2 },
  { id: 'sick', name: 'Sick Leave', code: 'SL', paid: true, annualQuotaDays: 8, allowHalfDay: true, status: 'active', system: false, sortOrder: 3 },
  { id: 'floating', name: 'Floating Holiday', code: 'FH', paid: true, annualQuotaDays: 2, allowHalfDay: false, status: 'active', system: false, sortOrder: 4 },
  { id: 'unpaid', name: 'Unpaid Leave', code: 'UL', paid: false, annualQuotaDays: null, allowHalfDay: true, status: 'active', system: true, sortOrder: 5 },
  { id: 'legacy-paid', name: 'Paid Leave (legacy)', code: 'PL', paid: true, annualQuotaDays: null, allowHalfDay: false, status: 'inactive', system: true, sortOrder: 1000 },
];

export interface LeaveTypeSeedStore {
  get(id: string): Promise<boolean>;
  create(id: string, value: SeedLeaveType & { createdAt: unknown; updatedAt: unknown }): Promise<void>;
  timestamp(): unknown;
}

export async function seedMissingLeaveTypes(store: LeaveTypeSeedStore): Promise<{
  created: string[];
  skipped: string[];
}> {
  const created: string[] = [];
  const skipped: string[] = [];
  for (const type of defaultLeaveTypes) {
    if (await store.get(type.id)) {
      skipped.push(type.id);
      continue;
    }
    const timestamp = store.timestamp();
    try {
      await store.create(type.id, { ...type, createdAt: timestamp, updatedAt: timestamp });
      created.push(type.id);
    } catch (error) {
      if (isAlreadyExists(error)) skipped.push(type.id);
      else throw error;
    }
  }
  return { created, skipped };
}

function isAlreadyExists(error: unknown): boolean {
  return typeof error === 'object' && error !== null && 'code' in error &&
    (error.code === 6 || error.code === 'already-exists');
}
