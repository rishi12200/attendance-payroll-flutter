export function workedMinutes(inTime: Date, outTime: Date): number {
  const elapsed = outTime.getTime() - inTime.getTime();
  if (!Number.isFinite(elapsed)) {
    throw new RangeError('Worked time requires valid Date values.');
  }
  return Math.max(0, Math.floor(elapsed / 60_000));
}

export interface AttendanceSettings {
  companyName: string;
  weeklyOffDays: number[];
  perDayBasis: 'calendar' | 'working';
  maxAccuracyMeters: number;
  rejectMockLocation: boolean;
  enforceCheckoutLocation: boolean;
}

export const DEFAULT_ATTENDANCE_SETTINGS: Readonly<AttendanceSettings> = {
  companyName: '',
  weeklyOffDays: [0],
  perDayBasis: 'calendar',
  maxAccuracyMeters: 100,
  rejectMockLocation: true,
  enforceCheckoutLocation: false,
};

export function attendanceSettingsFromDocument(
  document: Record<string, unknown> | undefined,
): AttendanceSettings {
  const companyName = document?.companyName ?? '';
  const weeklyOffDays = document?.weeklyOffDays ?? [0];
  const perDayBasis = document?.perDayBasis ?? 'calendar';
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
    typeof companyName !== 'string' ||
    !Array.isArray(weeklyOffDays) ||
    weeklyOffDays.some(
      (day) => !Number.isInteger(day) || day < 0 || day > 6,
    ) ||
    new Set(weeklyOffDays).size !== weeklyOffDays.length ||
    (perDayBasis !== 'calendar' && perDayBasis !== 'working') ||
    typeof maxAccuracyMeters !== 'number' ||
    !Number.isFinite(maxAccuracyMeters) ||
    maxAccuracyMeters < 0 ||
    typeof rejectMockLocation !== 'boolean' ||
    typeof enforceCheckoutLocation !== 'boolean'
  ) {
    throw new TypeError('Company attendance settings contain invalid values.');
  }
  return {
    companyName,
    weeklyOffDays: [...weeklyOffDays] as number[],
    perDayBasis,
    maxAccuracyMeters,
    rejectMockLocation,
    enforceCheckoutLocation,
  };
}
