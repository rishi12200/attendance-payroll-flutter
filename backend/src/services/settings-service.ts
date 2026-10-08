import { AppError } from '../errors/app-error';
import {
  attendanceSettingsFromDocument,
  type AttendanceSettings,
} from '../domain/attendance';

export interface SettingsStore {
  serverTimestamp(): unknown;
  getCompanySettings(): Promise<Record<string, unknown> | undefined>;
  mergeCompanySettings(values: Record<string, unknown>): Promise<void>;
}

export type SettingsPatch = Partial<
  Pick<
    AttendanceSettings,
    | 'companyName'
    | 'weeklyOffDays'
    | 'perDayBasis'
    | 'maxAccuracyMeters'
    | 'rejectMockLocation'
    | 'enforceCheckoutLocation'
  >
>;

export class SettingsService {
  constructor(private readonly store: SettingsStore) {}

  async getSettings(caller: { role: string }): Promise<Record<string, unknown>> {
    this.requireAdmin(caller.role);
    const document = await this.store.getCompanySettings();
    return {
      ...attendanceSettingsFromDocument(document),
      ...(document?.editedBy === undefined ? {} : { editedBy: document.editedBy }),
      ...(document?.updatedAt === undefined ? {} : { updatedAt: document.updatedAt }),
    };
  }

  async updateSettings(
    caller: { uid: string; role: string },
    changes: SettingsPatch,
  ): Promise<Record<string, unknown>> {
    this.requireAdmin(caller.role);
    if (Object.keys(changes).length === 0) {
      throw new AppError(
        400,
        'VALIDATION_ERROR',
        'At least one setting must be provided.',
      );
    }
    await this.store.mergeCompanySettings({
      ...changes,
      editedBy: caller.uid,
      updatedAt: this.store.serverTimestamp(),
    });
    return this.getSettings(caller);
  }

  private requireAdmin(role: string): void {
    if (role !== 'admin') {
      throw new AppError(403, 'FORBIDDEN', 'Only admins can manage settings.');
    }
  }
}
