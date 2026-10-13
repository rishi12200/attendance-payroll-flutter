import assert from 'node:assert/strict';
import test from 'node:test';
import { expandStateToBranchIds, holidayAppliesToBranch, holidayNameMap, holidayScopesOverlap, normalizeHoliday } from './holidays';

test('normalizes legacy date-keyed holiday documents and ignores invalid dates', () => {
  assert.deepEqual(normalizeHoliday('2026-10-02', { name: ' Founders Day ' }), {
    id: '2026-10-02', date: '2026-10-02', name: 'Founders Day', scope: 'all', branchIds: [],
  });
  assert.equal(normalizeHoliday('not-a-date', { name: 'Bad' }), undefined);
});

test('branch scope filters employees and null primary branches receive all scope only', () => {
  const all = { scope: 'all' as const };
  const scoped = { scope: 'branches' as const, branchIds: ['branch-a'] };
  assert.equal(holidayAppliesToBranch(all, null), true);
  assert.equal(holidayAppliesToBranch(scoped, null), false);
  assert.equal(holidayAppliesToBranch(scoped, 'branch-a'), true);
  assert.equal(holidayAppliesToBranch(scoped, 'branch-b'), false);
});

test('same date names are sorted and joined; overlaps depend on branch intersection', () => {
  assert.deepEqual(holidayNameMap([
    { date: '2026-10-02', name: 'Regional', scope: 'branches', branchIds: ['a'] },
    { date: '2026-10-02', name: 'National', scope: 'all', branchIds: [] },
  ]), { '2026-10-02': 'National, Regional' });
  assert.equal(holidayScopesOverlap({ scope: 'branches', branchIds: ['a'] }, { scope: 'branches', branchIds: ['b'] }), false);
  assert.equal(holidayScopesOverlap({ scope: 'all' }, { scope: 'branches', branchIds: ['b'] }), true);
});

test('state expansion selects active branches case insensitively and sorts ids', () => {
  assert.deepEqual(expandStateToBranchIds(' tamil nadu ', [
    { id: 'z', state: 'Tamil Nadu', status: 'active' },
    { id: 'b', state: 'TAMIL NADU', status: 'active' },
    { id: 'inactive', state: 'Tamil Nadu', status: 'inactive' },
    { id: 'other', state: 'Kerala', status: 'active' },
  ]), ['b', 'z']);
});
