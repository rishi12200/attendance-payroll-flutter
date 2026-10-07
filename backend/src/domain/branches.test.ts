import assert from 'node:assert/strict';
import test from 'node:test';
import {
  BRANCH_LATITUDE_MAX,
  BRANCH_LATITUDE_MIN,
  BRANCH_LONGITUDE_MAX,
  BRANCH_LONGITUDE_MIN,
  BRANCH_RADIUS_MAX_METERS,
  BRANCH_RADIUS_MIN_METERS,
  haversineDistanceMeters,
  isValidBranchRadius,
  isValidLatitude,
  isValidLongitude,
} from './branches';

test('validates branch coordinate and radius boundaries', () => {
  assert.equal(isValidLatitude(BRANCH_LATITUDE_MIN), true);
  assert.equal(isValidLatitude(BRANCH_LATITUDE_MAX), true);
  assert.equal(isValidLatitude(-90.01), false);
  assert.equal(isValidLatitude(90.01), false);
  assert.equal(isValidLatitude(Number.NaN), false);

  assert.equal(isValidLongitude(BRANCH_LONGITUDE_MIN), true);
  assert.equal(isValidLongitude(BRANCH_LONGITUDE_MAX), true);
  assert.equal(isValidLongitude(-180.01), false);
  assert.equal(isValidLongitude(180.01), false);

  assert.equal(isValidBranchRadius(BRANCH_RADIUS_MIN_METERS), true);
  assert.equal(isValidBranchRadius(BRANCH_RADIUS_MAX_METERS), true);
  assert.equal(isValidBranchRadius(19), false);
  assert.equal(isValidBranchRadius(1001), false);
  assert.equal(isValidBranchRadius(20.5), false);
});

test('calculates zero distance and a short distance near 100 metres', () => {
  assert.equal(haversineDistanceMeters(13.0827, 80.2707, 13.0827, 80.2707), 0);
  const distance = haversineDistanceMeters(0, 0, 0, 0.0009);
  assert.ok(distance > 99 && distance < 101, `distance was ${distance}m`);
});

test('matches a known long-distance coordinate pair', () => {
  const distance = haversineDistanceMeters(
    40.7128,
    -74.006,
    34.0522,
    -118.2437,
  );
  assert.ok(distance > 3_935_000 && distance < 3_945_000);
});
