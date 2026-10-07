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
