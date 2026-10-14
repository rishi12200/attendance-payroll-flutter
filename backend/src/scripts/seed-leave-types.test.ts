import assert from 'node:assert/strict';
import test from 'node:test';
import { defaultLeaveTypes, seedMissingLeaveTypes, type LeaveTypeSeedStore, type SeedLeaveType } from './seed-leave-types-core';

class FakeSeedStore implements LeaveTypeSeedStore {
  readonly values = new Map<string, SeedLeaveType & { createdAt: unknown; updatedAt: unknown }>();
  timestampCount = 0;
  timestamp() { this.timestampCount += 1; return `time-${this.timestampCount}`; }
  async get(id: string) { return this.values.has(id); }
  async create(id: string, value: SeedLeaveType & { createdAt: unknown; updatedAt: unknown }) {
    if (this.values.has(id)) throw Object.assign(new Error('exists'), { code: 6 });
    this.values.set(id, value);
  }
}

test('seeds fixed leave type ids once and preserves existing administrator edits', async () => {
  const store = new FakeSeedStore();
  store.values.set('annual', {
    ...defaultLeaveTypes[0]!, name: 'Edited annual', code: 'EA', createdAt: 'old', updatedAt: 'old',
  });
  const first = await seedMissingLeaveTypes(store);
  assert.deepEqual(first.created, ['casual', 'sick', 'floating', 'unpaid', 'legacy-paid']);
  assert.deepEqual(first.skipped, ['annual']);
  assert.equal(store.values.get('annual')?.name, 'Edited annual');
  const second = await seedMissingLeaveTypes(store);
  assert.deepEqual(second.created, []);
  assert.deepEqual(second.skipped, ['annual', 'casual', 'sick', 'floating', 'unpaid', 'legacy-paid']);
  assert.equal(store.values.get('legacy-paid')?.status, 'inactive');
});
