import 'dart:async';

import 'package:geolocator/geolocator.dart';

enum LocationFailureReason {
  serviceDisabled,
  permissionDenied,
  permissionDeniedForever,
  timeout,
  unknown,
}

sealed class LocationResult {
  const LocationResult();
}

class LocationSuccess extends LocationResult {
  const LocationSuccess({
    required this.latitude,
    required this.longitude,
    required this.accuracy,
  });

  final double latitude;
  final double longitude;
  final double accuracy;
}

class LocationFailure extends LocationResult {
  const LocationFailure(this.reason);

  final LocationFailureReason reason;
}

abstract interface class LocationService {
  Future<LocationResult> getCurrentPosition();
  Future<bool> openSettings(LocationFailureReason reason);
}

class GeolocatorLocationService implements LocationService {
  const GeolocatorLocationService();

  @override
  Future<LocationResult> getCurrentPosition() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        return const LocationFailure(LocationFailureReason.serviceDisabled);
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.deniedForever) {
        return const LocationFailure(
          LocationFailureReason.permissionDeniedForever,
        );
      }
      if (permission == LocationPermission.denied) {
        return const LocationFailure(LocationFailureReason.permissionDenied);
      }
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 15),
        ),
      );
      return LocationSuccess(
        latitude: position.latitude,
        longitude: position.longitude,
        accuracy: position.accuracy,
      );
    } on LocationServiceDisabledException {
      return const LocationFailure(LocationFailureReason.serviceDisabled);
    } on PermissionDeniedException {
      return const LocationFailure(LocationFailureReason.permissionDenied);
    } on TimeoutException {
      return const LocationFailure(LocationFailureReason.timeout);
    } catch (_) {
      return const LocationFailure(LocationFailureReason.unknown);
    }
  }

  @override
  Future<bool> openSettings(LocationFailureReason reason) {
    return switch (reason) {
      LocationFailureReason.serviceDisabled => Geolocator.openLocationSettings(),
      LocationFailureReason.permissionDeniedForever =>
        Geolocator.openAppSettings(),
      _ => Future.value(false),
    };
  }
}
