export function formatEmpCode(sequence: number): string {
  if (!Number.isSafeInteger(sequence) || sequence < 1) {
    throw new RangeError('Employee sequence must be a positive safe integer.');
  }
  return `EMP${String(sequence).padStart(3, '0')}`;
}
