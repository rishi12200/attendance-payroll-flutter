import assert from 'node:assert/strict';
import test from 'node:test';
import { patchSettingsSchema } from './settings-schemas';

test('validates the optional leave year start month between 1 and 12', () => {
  assert.deepEqual(patchSettingsSchema.parse({ leaveYearStartMonth: 4 }), { leaveYearStartMonth: 4 });
  assert.equal(patchSettingsSchema.safeParse({ leaveYearStartMonth: 0 }).success, false);
  assert.equal(patchSettingsSchema.safeParse({ leaveYearStartMonth: 13 }).success, false);
  assert.equal(patchSettingsSchema.safeParse({ leaveYearStartMonth: 1.5 }).success, false);
});
