export function workedMinutes(inTime: Date, outTime: Date): number {
  const elapsed = outTime.getTime() - inTime.getTime();
  if (!Number.isFinite(elapsed)) {
    throw new RangeError('Worked time requires valid Date values.');
  }
  return Math.max(0, Math.floor(elapsed / 60_000));
}

export interface AttendanceSettings {
  maxAccuracyMeters: number;
  rejectMockLocation: boolean;
  enforceCheckoutLocation: boolean;
}

export const DEFAULT_ATTENDANCE_SETTINGS: Readonly<AttendanceSettings> = {
  maxAccuracyMeters: 100,
  rejectMockLocation: true,
  enforceCheckoutLocation: false,
};

export function attendanceSettingsFromDocument(
  document: Record<string, unknown> | undefined,
): AttendanceSettings {
  const maxAccuracyMeters =
    document?.maxAccuracyMeters ??
    DEFAULT_ATTENDANCE_SETTINGS.maxAccuracyMeters;
  const rejectMockLocation =
    document?.rejectMockLocation ??
    DEFAULT_ATTENDANCE_SETTINGS.rejectMockLocation;
  const enforceCheckoutLocation =
    document?.enforceCheckoutLocation ??
    DEFAULT_ATTENDANCE_SETTINGS.enforceCheckoutLocation;

  if (
    typeof maxAccuracyMeters !== 'number' ||
    !Number.isFinite(maxAccuracyMeters) ||
    maxAccuracyMeters < 0 ||
    typeof rejectMockLocation !== 'boolean' ||
    typeof enforceCheckoutLocation !== 'boolean'
  ) {
    throw new TypeError('Company attendance settings contain invalid values.');
  }
  return {
    maxAccuracyMeters,
    rejectMockLocation,
    enforceCheckoutLocation,
  };
}
