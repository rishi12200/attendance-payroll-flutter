import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/app_exception.dart';
import '../../../features/branches/data/branches_providers.dart';
import '../../../features/branches/data/location_providers.dart';
import '../../../features/branches/domain/location_service.dart';
import '../data/attendance_providers.dart';
import '../data/attendance_repository.dart';
import '../data/install_id_store.dart';
import 'attendance.dart';
import 'attendance_helpers.dart';

final employeeBranchesProvider = FutureProvider(
  (ref) => ref.watch(branchRepositoryProvider).listBranches(),
  retry: (_, _) => null,
);

const _bootstrapMonth = '2000-01';

final attendanceControllerProvider =
    NotifierProvider<AttendanceController, AttendanceHomeState>(
      AttendanceController.new,
    );

sealed class AttendanceHomeState {
  const AttendanceHomeState();

  bool get isWorking => false;
  String? get feedback => null;
  LocationFailureReason? get locationFailure => null;
}

class AttendanceLoading extends AttendanceHomeState {
  const AttendanceLoading();
}

class AttendanceNotCheckedIn extends AttendanceHomeState {
  const AttendanceNotCheckedIn({
    required this.today,
    required this.serverTime,
    this.working = false,
    this.feedbackMessage,
    this.failureReason,
  });

  final String today;
  final String serverTime;
  final bool working;
  final String? feedbackMessage;
  final LocationFailureReason? failureReason;

  @override
  bool get isWorking => working;
  @override
  String? get feedback => feedbackMessage;
  @override
  LocationFailureReason? get locationFailure => failureReason;
}

class AttendanceCheckedIn extends AttendanceHomeState {
  const AttendanceCheckedIn({
    required this.today,
    required this.date,
    required this.inTime,
    required this.branchName,
    required this.serverTime,
    this.working = false,
    this.feedbackMessage,
    this.failureReason,
  });

  final String today;
  final String date;
  final String inTime;
  final String branchName;
  final String serverTime;
  final bool working;
  final String? feedbackMessage;
  final LocationFailureReason? failureReason;

  @override
  bool get isWorking => working;
  @override
  String? get feedback => feedbackMessage;
  @override
  LocationFailureReason? get locationFailure => failureReason;
}

class AttendanceCompleted extends AttendanceHomeState {
  const AttendanceCompleted({
    required this.today,
    required this.date,
    required this.inTime,
    required this.outTime,
    required this.workedMinutes,
    required this.serverTime,
    this.working = false,
    this.feedbackMessage,
    this.failureReason,
  });

  final String today;
  final String date;
  final String inTime;
  final String outTime;
  final int workedMinutes;
  final String serverTime;
  final bool working;
  final String? feedbackMessage;
  final LocationFailureReason? failureReason;

  @override
  bool get isWorking => working;
  @override
  String? get feedback => feedbackMessage;
  @override
  LocationFailureReason? get locationFailure => failureReason;
}

class AttendanceLoadError extends AttendanceHomeState {
  const AttendanceLoadError(this.error);

  final Object error;
}

class AttendanceController extends Notifier<AttendanceHomeState> {
  bool _punchInProgress = false;

  AttendanceRepository get _repository =>
      ref.read(attendanceRepositoryProvider);
  InstallIdStore get _installIdStore => ref.read(installIdStoreProvider);
  LocationService get _locationService => ref.read(locationServiceProvider);
  @override
  AttendanceHomeState build() {
    scheduleMicrotask(refresh);
    return const AttendanceLoading();
  }

  Future<void> refresh({bool allowWhileWorking = false}) async {
    final stateBeforeLoad = state;
    if (stateBeforeLoad.isWorking && !allowWhileWorking) return;
    try {
      var month = switch (stateBeforeLoad) {
        AttendanceNotCheckedIn(:final today) => today.substring(0, 7),
        AttendanceCheckedIn(:final today) => today.substring(0, 7),
        AttendanceCompleted(:final today) => today.substring(0, 7),
        _ => _bootstrapMonth,
      };
      var current = await _repository.getMyMonth(month);
      for (var attempt = 0; attempt < 2; attempt++) {
        final serverMonth = current.today.substring(0, 7);
        if (serverMonth == month && current.month == month) break;
        month = serverMonth;
        current = await _repository.getMyMonth(serverMonth);
      }
      if (current.today.substring(0, 7) != current.month) {
        throw const FormatException(
          'The server returned attendance for a different month than today.',
        );
      }

      final days = <String, AttendanceDay>{...current.days};
      if (current.today.substring(8) == '01') {
        final previousMonth = _previousMonth(month);
        final previous = await _repository.getMyMonth(previousMonth);
        days.addAll(previous.days);
      }
      try {
        await ref.read(employeeBranchesProvider.future);
      } catch (_) {
        // Attendance state remains usable if branch names are unavailable.
      }
      state = _stateFromServer(current, days);
    } catch (error) {
      state = AttendanceLoadError(error);
    }
  }

  Future<void> checkIn() => _punch(checkingIn: true);

  Future<void> checkOut() => _punch(checkingIn: false);

  Future<void> _punch({required bool checkingIn}) async {
    if (_punchInProgress ||
        state.isWorking ||
        state is AttendanceLoading ||
        state is AttendanceLoadError) {
      return;
    }
    _punchInProgress = true;
    state = _setWorking(state, true, clearFeedback: true);
    try {
      final positionResult = await _locationService.getCurrentPosition();
      if (positionResult case LocationFailure(:final reason)) {
        state = _setFeedback(
          _setWorking(state, false),
          locationFailureMessage(reason),
          reason: reason,
        );
        return;
      }

      final position = positionResult as LocationSuccess;
      final deviceId = await _installIdStore.getOrCreate();
      final payload = <String, Object?>{
        'lat': position.latitude,
        'lng': position.longitude,
        'accuracy': position.accuracy,
        'deviceId': deviceId,
        'isMocked': position.isMocked,
      };
      if (checkingIn) {
        await _repository.checkIn(payload);
      } else {
        await _repository.checkOut(payload);
      }
      await refresh(allowWhileWorking: true);
    } on AppException catch (error) {
      if (const {
        'ALREADY_CHECKED_IN',
        'ALREADY_CHECKED_OUT',
        'NOT_CHECKED_IN',
      }.contains(error.code)) {
        await refresh(allowWhileWorking: true);
      } else {
        state = _setWorking(state, false);
      }
      state = _setFeedback(
        state,
        attendanceErrorMessage(error),
      );
    } catch (error) {
      state = _setWorking(state, false);
      state = _setFeedback(
        state,
        'Could not complete attendance. Please try again.',
      );
    } finally {
      _punchInProgress = false;
      if (state.isWorking) state = _setWorking(state, false);
    }
  }

  AttendanceHomeState _stateFromServer(
    MonthAttendance current,
    Map<String, AttendanceDay> days,
  ) {
    final open = openCheckIn(days, current.serverTime);
    if (open != null) {
      final branchName = _branchName(open.day.inBranchId);
      return AttendanceCheckedIn(
        today: current.today,
        date: open.date,
        inTime: open.day.inTime!,
        branchName: branchName,
        serverTime: current.serverTime,
      );
    }

    final todayDay = days[current.today];
    final completed = todayDay != null && todayDay.inTime != null
        ? todayDay
        : _mostRecentCompletedWithinADay(days, current.serverTime);
    if (completed?.inTime != null && completed?.outTime != null) {
      return AttendanceCompleted(
        today: current.today,
        date: _dateOf(days, completed!),
        inTime: completed.inTime!,
        outTime: completed.outTime!,
        workedMinutes: completed.workedMinutes ?? 0,
        serverTime: current.serverTime,
      );
    }
    return AttendanceNotCheckedIn(
      today: current.today,
      serverTime: current.serverTime,
    );
  }

  AttendanceDay? _mostRecentCompletedWithinADay(
    Map<String, AttendanceDay> days,
    String serverTime,
  ) {
    final now = DateTime.parse(serverTime).toUtc();
    AttendanceDay? newest;
    DateTime? newestTime;
    for (final day in days.values) {
      if (day.inTime == null || day.outTime == null) continue;
      final inTime = DateTime.tryParse(day.inTime!)?.toUtc();
      if (inTime == null) continue;
      final elapsed = now.difference(inTime);
      if (elapsed.isNegative || elapsed >= const Duration(days: 1)) continue;
      if (newestTime == null || inTime.isAfter(newestTime)) {
        newest = day;
        newestTime = inTime;
      }
    }
    return newest;
  }

  String _dateOf(Map<String, AttendanceDay> days, AttendanceDay day) =>
      days.entries
          .firstWhere((entry) => identical(entry.value, day))
          .key;

  String _branchName(String? branchId) {
    if (branchId == null) return 'your assigned branch';
    final branches = ref.read(employeeBranchesProvider).asData?.value;
    for (final branch in branches ?? const []) {
      if (branch.id == branchId) return branch.name;
    }
    return branchId;
  }

  AttendanceHomeState _setWorking(
    AttendanceHomeState current,
    bool working, {
    bool clearFeedback = false,
  }) {
    final message = clearFeedback ? null : current.feedback;
    final failure = clearFeedback ? null : current.locationFailure;
    return switch (current) {
      AttendanceNotCheckedIn(:final today, :final serverTime) =>
        AttendanceNotCheckedIn(
          today: today,
          serverTime: serverTime,
          working: working,
          feedbackMessage: message,
          failureReason: failure,
        ),
      AttendanceCheckedIn(
        :final today,
        :final date,
        :final inTime,
        :final branchName,
        :final serverTime,
      ) =>
        AttendanceCheckedIn(
          today: today,
          date: date,
          inTime: inTime,
          branchName: branchName,
          serverTime: serverTime,
          working: working,
          feedbackMessage: message,
          failureReason: failure,
        ),
      AttendanceCompleted(
        :final today,
        :final date,
        :final inTime,
        :final outTime,
        :final workedMinutes,
        :final serverTime,
      ) =>
        AttendanceCompleted(
          today: today,
          date: date,
          inTime: inTime,
          outTime: outTime,
          workedMinutes: workedMinutes,
          serverTime: serverTime,
          working: working,
          feedbackMessage: message,
          failureReason: failure,
        ),
      AttendanceLoading() || AttendanceLoadError() => current,
    };
  }

  AttendanceHomeState _setFeedback(
    AttendanceHomeState current,
    String message, {
    LocationFailureReason? reason,
  }) {
    return switch (current) {
      AttendanceNotCheckedIn(:final today, :final serverTime, :final working) =>
        AttendanceNotCheckedIn(
          today: today,
          serverTime: serverTime,
          working: working,
          feedbackMessage: message,
          failureReason: reason,
        ),
      AttendanceCheckedIn(
        :final today,
        :final date,
        :final inTime,
        :final branchName,
        :final serverTime,
        :final working,
      ) =>
        AttendanceCheckedIn(
          today: today,
          date: date,
          inTime: inTime,
          branchName: branchName,
          serverTime: serverTime,
          working: working,
          feedbackMessage: message,
          failureReason: reason,
        ),
      AttendanceCompleted(
        :final today,
        :final date,
        :final inTime,
        :final outTime,
        :final workedMinutes,
        :final serverTime,
        :final working,
      ) =>
        AttendanceCompleted(
          today: today,
          date: date,
          inTime: inTime,
          outTime: outTime,
          workedMinutes: workedMinutes,
          serverTime: serverTime,
          working: working,
          feedbackMessage: message,
          failureReason: reason,
        ),
      AttendanceLoading() || AttendanceLoadError() => current,
    };
  }

  String _previousMonth(String month) {
    final year = int.parse(month.substring(0, 4));
    final monthNumber = int.parse(month.substring(5, 7));
    if (monthNumber == 1) {
      return '${year - 1}-12';
    }
    return '$year-${(monthNumber - 1).toString().padLeft(2, '0')}';
  }
}

String locationFailureMessage(LocationFailureReason reason) => switch (reason) {
  LocationFailureReason.serviceDisabled =>
    'Location services are off. Turn them on to continue.',
  LocationFailureReason.permissionDenied =>
    'Location permission was denied. Allow location access to continue.',
  LocationFailureReason.permissionDeniedForever =>
    'Location permission is blocked. Open app settings to allow location access.',
  LocationFailureReason.timeout =>
    'Could not get an accurate location in time. Move to an open area and retry.',
  LocationFailureReason.unknown =>
    'Could not get your location. Please try again.',
};

String attendanceErrorMessage(AppException error) {
  final details = error.details;
  switch (error.code) {
    case 'OUTSIDE_GEOFENCE':
      final distance = details['distanceMeters'];
      final radius = details['radiusMeters'];
      final branchName = details['nearestBranchName'];
      if (distance is num && radius is num && branchName is String) {
        return 'You are ${formatDistance(distance.toDouble())} from $branchName; '
            'you need to be within ${radius.round()} m.';
      }
      return error.message;
    case 'ACCURACY_TOO_LOW':
      final accuracy = details['accuracy'];
      if (accuracy is num) {
        return 'GPS accuracy is too low (${accuracy.round()} m). '
            'Move to an open area and try again.';
      }
      return error.message;
    case 'MOCK_LOCATION':
      return 'Mock locations are not allowed.';
    case 'NO_BRANCH_ASSIGNED':
      return 'No branch is assigned to you yet. Ask your admin.';
    case 'MONTH_LOCKED':
      return error.message;
  }
  if (error.statusCode == 403) {
    return "Your account can't check in. Contact your admin.";
  }
  return error.message;
}

String formatDistance(double meters) {
  if (meters < 1000) return '${meters.round()} m';
  return '${(meters / 1000).toStringAsFixed(1)} km';
}
