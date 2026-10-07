import assert from 'node:assert/strict';
import test from 'node:test';
import {
  BRANCH_LATITUDE_MAX,
  BRANCH_LATITUDE_MIN,
  BRANCH_LONGITUDE_MAX,
  BRANCH_LONGITUDE_MIN,
  BRANCH_RADIUS_MAX_METERS,
  BRANCH_RADIUS_MIN_METERS,
  evaluateGeofence,
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

const geofenceBranch = {
  id: 'branch-1',
  name: 'Test Office',
  lat: 0,
  lng: 0,
  radiusMeters: 100,
};

test('geofence accepts locations inside and rejects points just outside', () => {
  const inside = evaluateGeofence({
    lat: 0,
    lng: 0.0008,
    accuracy: 0,
    branches: [geofenceBranch],
  });
  assert.equal(inside.inside, true);
  assert.equal(inside.nearestBranch?.id, 'branch-1');

  const outside = evaluateGeofence({
    lat: 0,
    lng: 0.00091,
    accuracy: 0,
    branches: [geofenceBranch],
  });
  assert.equal(outside.inside, false);
  assert.ok((outside.nearestBranch?.distanceMeters ?? 0) > 100);
});

test('geofence applies accuracy tolerance but caps it at 50 metres', () => {
  const cappedBoundary = evaluateGeofence({
    lat: 0,
    lng: 0.00126,
    accuracy: 50,
    branches: [geofenceBranch],
  });
  assert.equal(cappedBoundary.inside, true);

  const overCap = evaluateGeofence({
    lat: 0,
    lng: 0.00144,
    accuracy: 100,
    branches: [geofenceBranch],
  });
  assert.equal(overCap.inside, false);
});

test('geofence reports the nearest of several branches', () => {
  const evaluation = evaluateGeofence({
    lat: 0,
    lng: 0.01,
    accuracy: 0,
    branches: [
      { ...geofenceBranch, id: 'far', lng: 0.02 },
      { ...geofenceBranch, id: 'near', lng: 0.0101 },
    ],
  });
  assert.equal(evaluation.nearestBranch?.id, 'near');
});

test('geofence returns no nearest branch for an empty list', () => {
  assert.deepEqual(
    evaluateGeofence({ lat: 0, lng: 0, accuracy: 1, branches: [] }),
    { nearestBranch: null, inside: false },
  );
});
