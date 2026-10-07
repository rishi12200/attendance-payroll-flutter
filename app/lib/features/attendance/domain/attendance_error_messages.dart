import '../../../core/api/app_exception.dart';
import '../../../features/branches/domain/location_service.dart';

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
