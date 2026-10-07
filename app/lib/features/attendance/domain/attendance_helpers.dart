import 'dart:math' as math;

import '../../branches/domain/branch.dart';
import 'attendance.dart';

const _earthRadiusMeters = 6371000.0;
const _istOffset = Duration(hours: 5, minutes: 30);
const _day = Duration(days: 1);

double haversineDistanceMeters(
  double latitudeA,
  double longitudeA,
  double latitudeB,
  double longitudeB,
) {
  const radians = math.pi / 180;
  final latitudeDelta = (latitudeB - latitudeA) * radians;
  final longitudeDelta = (longitudeB - longitudeA) * radians;
  final haversine =
      math.pow(math.sin(latitudeDelta / 2), 2) +
      math.cos(latitudeA * radians) *
          math.cos(latitudeB * radians) *
          math.pow(math.sin(longitudeDelta / 2), 2);
  return 2 * _earthRadiusMeters * math.asin(math.sqrt(haversine));
}

class AttendancePosition {
  const AttendancePosition({
    required this.latitude,
    required this.longitude,
    required this.accuracy,
  });

  final double latitude;
  final double longitude;
  final double accuracy;
}

class BranchDistanceEstimate {
  const BranchDistanceEstimate({
    required this.branch,
    required this.distanceMeters,
    required this.insideEstimate,
  });

  final Branch branch;
  final double distanceMeters;
  final bool insideEstimate;
}

BranchDistanceEstimate? nearestBranch(
  AttendancePosition position,
  List<Branch> branches,
) {
  BranchDistanceEstimate? nearest;
  for (final branch in branches) {
    final distance = haversineDistanceMeters(
      position.latitude,
      position.longitude,
      branch.lat,
      branch.lng,
    );
    if (nearest == null || distance < nearest.distanceMeters) {
      nearest = BranchDistanceEstimate(
        branch: branch,
        distanceMeters: distance,
        insideEstimate:
            distance - math.min(position.accuracy, 50) <= branch.radiusMeters,
      );
    }
  }
  return nearest;
}

String formatIstTime(String isoUtc) {
  final utc = DateTime.parse(isoUtc).toUtc();
  final ist = utc.add(_istOffset);
  final hour = ist.hour % 12 == 0 ? 12 : ist.hour % 12;
  final hh = hour.toString().padLeft(2, '0');
  final mm = ist.minute.toString().padLeft(2, '0');
  final suffix = ist.hour < 12 ? 'AM' : 'PM';
  return '$hh:$mm $suffix';
}

String formatWorkedMinutes(int minutes) {
  if (minutes < 1) return 'less than a minute';
  final hours = minutes ~/ 60;
  final remainder = minutes % 60;
  if (hours == 0) return '$remainder min';
  if (remainder == 0) return '$hours h';
  return '$hours h $remainder min';
}

class OpenCheckIn {
  const OpenCheckIn({
    required this.date,
    required this.day,
    required this.inTime,
  });

  final String date;
  final AttendanceDay day;
  final DateTime inTime;
}

OpenCheckIn? openCheckIn(
  Map<String, AttendanceDay> days,
  String serverTime,
) {
  final now = DateTime.parse(serverTime).toUtc();
  OpenCheckIn? mostRecent;
  for (final entry in days.entries) {
    final rawInTime = entry.value.inTime;
    if (rawInTime == null || entry.value.outTime != null) continue;
    final inTime = DateTime.tryParse(rawInTime)?.toUtc();
    if (inTime == null) continue;
    final elapsed = now.difference(inTime);
    if (elapsed.isNegative || elapsed >= _day) continue;
    if (mostRecent == null || inTime.isAfter(mostRecent.inTime)) {
      mostRecent = OpenCheckIn(
        date: entry.key,
        day: entry.value,
        inTime: inTime,
      );
    }
  }
  return mostRecent;
}
