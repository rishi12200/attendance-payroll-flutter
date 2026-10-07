import assert from 'node:assert/strict';
import test from 'node:test';
import { createBranchSchema, listBranchesQuerySchema, patchBranchSchema } from './branch-schemas';

const validBranch = {
  name: ' Chennai Office ',
  address: 'Example Road',
  state: ' Tamil Nadu ',
  lat: 13.0827,
  lng: 80.2707,
  radiusMeters: 100,
};

test('trims required branch text and validates coordinates and radius', () => {
  const result = createBranchSchema.parse(validBranch);
  assert.equal(result.name, 'Chennai Office');
  assert.equal(result.state, 'Tamil Nadu');
  assert.equal(createBranchSchema.safeParse({ ...validBranch, lat: 91 }).success, false);
  assert.equal(createBranchSchema.safeParse({ ...validBranch, lng: -181 }).success, false);
  assert.equal(createBranchSchema.safeParse({ ...validBranch, radiusMeters: 20.5 }).success, false);
  assert.equal(createBranchSchema.safeParse({ ...validBranch, radiusMeters: 19 }).success, false);
  assert.equal(createBranchSchema.safeParse({ ...validBranch, unknown: true }).success, false);
});

test('patch accepts only branch fields and requires at least one', () => {
  assert.deepEqual(patchBranchSchema.parse({ name: ' New Name ' }), { name: 'New Name' });
  assert.equal(patchBranchSchema.safeParse({}).success, false);
  assert.equal(patchBranchSchema.safeParse({ status: 'inactive' }).success, false);
});

test('validates branch status filter', () => {
  assert.equal(listBranchesQuerySchema.parse({}).status, 'active');
  assert.equal(listBranchesQuerySchema.parse({ status: 'all' }).status, 'all');
  assert.equal(listBranchesQuerySchema.safeParse({ status: 'invalid' }).success, false);
});
