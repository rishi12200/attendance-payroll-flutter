import assert from 'node:assert/strict';
import test from 'node:test';
import { formatEmpCode } from './emp-code';

test('formats employee sequence numbers with at least three digits', () => {
  assert.equal(formatEmpCode(1), 'EMP001');
  assert.equal(formatEmpCode(25), 'EMP025');
  assert.equal(formatEmpCode(999), 'EMP999');
  assert.equal(formatEmpCode(1000), 'EMP1000');
});

test('rejects invalid employee sequence numbers', () => {
  assert.throws(() => formatEmpCode(0), RangeError);
  assert.throws(() => formatEmpCode(1.5), RangeError);
  assert.throws(() => formatEmpCode(Number.MAX_SAFE_INTEGER + 1), RangeError);
});
