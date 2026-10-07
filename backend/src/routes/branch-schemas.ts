import { z } from 'zod';
import {
  BRANCH_LATITUDE_MAX,
  BRANCH_LATITUDE_MIN,
  BRANCH_LONGITUDE_MAX,
  BRANCH_LONGITUDE_MIN,
  BRANCH_RADIUS_MAX_METERS,
  BRANCH_RADIUS_MIN_METERS,
} from '../domain/branches';

const branchFields = {
  name: z.string().trim().min(1),
  address: z.string().trim().optional(),
  state: z.string().trim().min(1),
  lat: z.number().finite().min(BRANCH_LATITUDE_MIN).max(BRANCH_LATITUDE_MAX),
  lng: z.number().finite().min(BRANCH_LONGITUDE_MIN).max(BRANCH_LONGITUDE_MAX),
  radiusMeters: z
    .number()
    .int()
    .min(BRANCH_RADIUS_MIN_METERS)
    .max(BRANCH_RADIUS_MAX_METERS),
};

export const createBranchSchema = z.strictObject(branchFields);

export const patchBranchSchema = z
  .strictObject({
    name: branchFields.name.optional(),
    address: branchFields.address,
    state: branchFields.state.optional(),
    lat: branchFields.lat.optional(),
    lng: branchFields.lng.optional(),
    radiusMeters: branchFields.radiusMeters.optional(),
  })
  .refine(
    (value) => Object.keys(value).length > 0,
    'At least one editable field is required.',
  );

export const branchIdParamsSchema = z.strictObject({
  id: z.string().trim().min(1),
});

export const listBranchesQuerySchema = z.strictObject({
  status: z.enum(['active', 'inactive', 'all']).default('active'),
});
