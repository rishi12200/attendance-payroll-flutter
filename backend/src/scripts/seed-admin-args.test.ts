import assert from 'node:assert/strict';
import test from 'node:test';
import { parseSeedUserArguments } from './seed-admin-args';

test('defaults the seed role to admin', () => {
  assert.deepEqual(
    parseSeedUserArguments(['--email', 'admin@example.com', '--password', 'test-pass-123']),
    { email: 'admin@example.com', password: 'test-pass-123', role: 'admin' },
  );
});

test('accepts employee role in any argument order', () => {
  assert.deepEqual(
    parseSeedUserArguments([
      '--role',
      'employee',
      '--password',
      'test-pass-123',
      '--email',
      'employee@example.com',
    ]),
    { email: 'employee@example.com', password: 'test-pass-123', role: 'employee' },
  );
});

test('rejects invalid roles and malformed arguments', () => {
  assert.equal(
    parseSeedUserArguments([
      '--email',
      'employee@example.com',
      '--password',
      'test-pass-123',
      '--role',
      'owner',
    ]),
    undefined,
  );
  assert.equal(parseSeedUserArguments(['--email', 'admin@example.com']), undefined);
});
