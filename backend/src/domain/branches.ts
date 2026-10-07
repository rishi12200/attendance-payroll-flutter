export const BRANCH_LATITUDE_MIN = -90;
export const BRANCH_LATITUDE_MAX = 90;
export const BRANCH_LONGITUDE_MIN = -180;
export const BRANCH_LONGITUDE_MAX = 180;
export const BRANCH_RADIUS_MIN_METERS = 20;
export const BRANCH_RADIUS_MAX_METERS = 1000;

const EARTH_RADIUS_METERS = 6_371_000;

export function isValidLatitude(value: number): boolean {
  return Number.isFinite(value) &&
    value >= BRANCH_LATITUDE_MIN &&
    value <= BRANCH_LATITUDE_MAX;
}

export function isValidLongitude(value: number): boolean {
  return Number.isFinite(value) &&
    value >= BRANCH_LONGITUDE_MIN &&
    value <= BRANCH_LONGITUDE_MAX;
}

export function isValidBranchRadius(value: number): boolean {
  return Number.isInteger(value) &&
    value >= BRANCH_RADIUS_MIN_METERS &&
    value <= BRANCH_RADIUS_MAX_METERS;
}

export function haversineDistanceMeters(
  latitudeA: number,
  longitudeA: number,
  latitudeB: number,
  longitudeB: number,
): number {
  const radians = Math.PI / 180;
  const latitudeDelta = (latitudeB - latitudeA) * radians;
  const longitudeDelta = (longitudeB - longitudeA) * radians;
  const haversine =
    Math.sin(latitudeDelta / 2) ** 2 +
    Math.cos(latitudeA * radians) *
      Math.cos(latitudeB * radians) *
      Math.sin(longitudeDelta / 2) ** 2;
  return 2 * EARTH_RADIUS_METERS * Math.asin(Math.sqrt(haversine));
}

export interface GeofenceBranch {
  id: string;
  name: string;
  lat: number;
  lng: number;
  radiusMeters: number;
}

export interface NearestGeofenceBranch {
  id: string;
  name: string;
  distanceMeters: number;
  radiusMeters: number;
}

export interface GeofenceEvaluation {
  nearestBranch: NearestGeofenceBranch | null;
  inside: boolean;
}

export function evaluateGeofence(input: {
  lat: number;
  lng: number;
  accuracy: number;
  branches: GeofenceBranch[];
}): GeofenceEvaluation {
  if (
    !Number.isFinite(input.lat) ||
    !Number.isFinite(input.lng) ||
    !Number.isFinite(input.accuracy) ||
    input.accuracy < 0
  ) {
    throw new RangeError('Geofence coordinates and accuracy must be finite.');
  }
  if (input.branches.length === 0) {
    return { nearestBranch: null, inside: false };
  }

  let nearest: NearestGeofenceBranch | null = null;
  for (const branch of input.branches) {
    const distanceMeters = haversineDistanceMeters(
      input.lat,
      input.lng,
      branch.lat,
      branch.lng,
    );
    if (nearest === null || distanceMeters < nearest.distanceMeters) {
      nearest = {
        id: branch.id,
        name: branch.name,
        distanceMeters,
        radiusMeters: branch.radiusMeters,
      };
    }
  }

  return {
    nearestBranch: nearest,
    inside:
      nearest!.distanceMeters - Math.min(input.accuracy, 50) <=
      nearest!.radiusMeters,
  };
}
