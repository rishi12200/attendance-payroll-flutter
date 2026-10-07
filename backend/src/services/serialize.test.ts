import assert from 'node:assert/strict';
import test from 'node:test';
import { Timestamp } from 'firebase-admin/firestore';
import { serialize } from './serialize';

test('recursively serializes Firestore Timestamps as ISO 8601 strings', () => {
  const createdAt = Timestamp.fromDate(new Date('2026-10-07T04:30:00.000Z'));
  const nestedAt = Timestamp.fromDate(new Date('2026-10-07T05:45:12.345Z'));
  const result = serialize({
    createdAt,
    history: [{ editedAt: nestedAt }],
    unchanged: 'value',
  });

  assert.deepEqual(result, {
    createdAt: '2026-10-07T04:30:00.000Z',
    history: [{ editedAt: '2026-10-07T05:45:12.345Z' }],
    unchanged: 'value',
  });
});
