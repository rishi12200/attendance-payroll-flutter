import assert from 'node:assert/strict';
import test from 'node:test';
import { expandStateToBranchIds, findOverlappingHolidays, holidayAppliesToBranch, holidayNameMap, holidayScopesOverlap, normalizeHoliday } from './holidays';

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

test('holiday overlap is determined by date and branch scope, never name', () => {
  const candidates = [
    {
      title: 'all overlaps all',
      existing: { id: 'old', date: '2026-10-02', name: 'Old', scope: 'all' as const },
      candidate: { date: '2026-10-02', name: 'New', scope: 'all' as const },
      overlaps: true,
    },
    {
      title: 'all overlaps branches',
      existing: { id: 'old', date: '2026-10-02', name: 'Old', scope: 'all' as const },
      candidate: { date: '2026-10-02', name: 'New', scope: 'branches' as const, branchIds: ['a'] },
      overlaps: true,
    },
    {
      title: 'intersecting branch scopes overlap',
      existing: { id: 'old', date: '2026-10-02', name: 'Old', scope: 'branches' as const, branchIds: ['a', 'b'] },
      candidate: { date: '2026-10-02', name: 'New', scope: 'branches' as const, branchIds: ['b', 'c'] },
      overlaps: true,
    },
    {
      title: 'disjoint branch scopes do not overlap',
      existing: { id: 'old', date: '2026-10-02', name: 'Old', scope: 'branches' as const, branchIds: ['a'] },
      candidate: { date: '2026-10-02', name: 'New', scope: 'branches' as const, branchIds: ['b'] },
      overlaps: false,
    },
    {
      title: 'same date with different names still overlaps',
      existing: { id: 'old', date: '2026-10-02', name: 'Different name', scope: 'all' as const },
      candidate: { date: '2026-10-02', name: 'Candidate name', scope: 'all' as const },
      overlaps: true,
    },
    {
      title: 'same name with different case still overlaps',
      existing: { id: 'old', date: '2026-10-02', name: 'founders day', scope: 'all' as const },
      candidate: { date: '2026-10-02', name: 'Founders Day', scope: 'all' as const },
      overlaps: true,
    },
    {
      title: 'different dates do not overlap',
      existing: { id: 'old', date: '2026-10-02', name: 'Same', scope: 'all' as const },
      candidate: { date: '2026-10-03', name: 'Same', scope: 'all' as const },
      overlaps: false,
    },
  ];

  for (const item of candidates) {
    const overlaps = findOverlappingHolidays([item.existing], item.candidate);
    assert.equal(overlaps.length > 0, item.overlaps, item.title);
  }
});

test('state expansion selects active branches case insensitively and sorts ids', () => {
  assert.deepEqual(expandStateToBranchIds(' tamil nadu ', [
    { id: 'z', state: 'Tamil Nadu', status: 'active' },
    { id: 'b', state: 'TAMIL NADU', status: 'active' },
    { id: 'inactive', state: 'Tamil Nadu', status: 'inactive' },
    { id: 'other', state: 'Kerala', status: 'active' },
  ]), ['b', 'z']);
});
