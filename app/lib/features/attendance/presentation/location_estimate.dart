import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/auth_providers.dart';
import '../../../features/branches/data/location_providers.dart';
import '../../../features/branches/domain/location_service.dart';
import '../domain/attendance_controller.dart';
import '../domain/attendance_helpers.dart';

sealed class LocationEstimate {
  const LocationEstimate();
}

class LocationEstimateNoBranches extends LocationEstimate {
  const LocationEstimateNoBranches();
}

class LocationEstimateUnavailable extends LocationEstimate {
  const LocationEstimateUnavailable(this.reason);

  final LocationFailureReason reason;
}

class LocationEstimateAvailable extends LocationEstimate {
  const LocationEstimateAvailable(this.value);

  final BranchDistanceEstimate value;
}

final locationEstimateProvider =
    FutureProvider.family<LocationEstimate, String>((ref, uid) async {
  if (ref.watch(signedInUidProvider) != uid) {
    return const LocationEstimateNoBranches();
  }
  final branches = await ref.watch(employeeBranchesProvider(uid).future);
  if (branches.isEmpty) return const LocationEstimateNoBranches();

  final result = await ref.watch(locationServiceProvider).getCurrentPosition();
  if (result case LocationFailure(:final reason)) {
    return LocationEstimateUnavailable(reason);
  }
  final position = result as LocationSuccess;
  final estimate = nearestBranch(
    AttendancePosition(
      latitude: position.latitude,
      longitude: position.longitude,
      accuracy: position.accuracy,
    ),
    branches,
  );
  if (estimate == null) return const LocationEstimateNoBranches();
  return LocationEstimateAvailable(estimate);
});
