import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/auth_providers.dart';
import 'attendance_repository.dart';
import 'install_id_store.dart';

final attendanceRepositoryProvider = Provider<AttendanceRepository>(
  (ref) => ApiAttendanceRepository(ref.watch(apiClientProvider)),
);

final installIdStoreProvider = Provider<InstallIdStore>(
  (ref) => const SharedPreferencesInstallIdStore(),
);
