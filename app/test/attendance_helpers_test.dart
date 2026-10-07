import 'package:app/features/attendance/domain/attendance.dart';
import 'package:app/features/attendance/domain/attendance_helpers.dart';
import 'package:app/features/branches/domain/branch.dart';
import 'package:flutter_test/flutter_test.dart';

Branch branch(String id, double latitude, double longitude, int radius) =>
    Branch(
      id: id,
      name: id,
      state: 'Tamil Nadu',
      lat: latitude,
      lng: longitude,
      radiusMeters: radius,
      status: BranchStatus.active,
      createdAt: '',
      updatedAt: '',
    );

void main() {
  test('Haversine handles zero distance and a known short distance', () {
    expect(haversineDistanceMeters(13, 80, 13, 80), 0);
    final distance = haversineDistanceMeters(0, 0, 0, 0.0009);
    expect(distance, closeTo(100, 1));
  });

  test('nearest branch selects the closest and estimates accuracy tolerance', () {
    final nearest = nearestBranch(
      const AttendancePosition(latitude: 0, longitude: 0, accuracy: 20),
      [branch('far', 0, 0.01, 100), branch('near', 0, 0.0009, 81)],
    );
    expect(nearest?.branch.id, 'near');
    expect(nearest?.distanceMeters, closeTo(100, 1));
    expect(nearest?.insideEstimate, isTrue);
    expect(
      nearestBranch(
        const AttendancePosition(latitude: 0, longitude: 0, accuracy: 100),
        [branch('near', 0, 0.0009, 55)],
      )?.insideEstimate,
      isTrue,
    );
    expect(
      nearestBranch(
        const AttendancePosition(latitude: 0, longitude: 0, accuracy: 0),
        [branch('near', 0, 0.0009, 55)],
      )?.insideEstimate,
      isFalse,
    );
    expect(
      nearestBranch(
        const AttendancePosition(latitude: 0, longitude: 0, accuracy: 0),
        [],
      ),
      isNull,
    );
  });

  test('formats UTC times in IST across the date boundary', () {
    expect(formatIstTime('2026-10-07T18:29:00.000Z'), '11:59 PM');
    expect(formatIstTime('2026-10-07T18:30:00.000Z'), '12:00 AM');
    expect(formatIstTime('2026-10-07T06:05:00.000Z'), '11:35 AM');
  });

  test('formats worked minutes including less than a minute', () {
    expect(formatWorkedMinutes(0), 'less than a minute');
    expect(formatWorkedMinutes(125), '2 h 5 min');
    expect(formatWorkedMinutes(60), '1 h');
    expect(formatWorkedMinutes(5), '5 min');
  });

  test('finds only the most recent open check-in less than 24 hours old', () {
    final days = {
      '2026-10-06': const AttendanceDay(
        status: 'P',
        inTime: '2026-10-06T12:00:00.000Z',
      ),
      '2026-10-07': const AttendanceDay(
        status: 'P',
        inTime: '2026-10-07T06:00:00.000Z',
        outTime: '2026-10-07T09:00:00.000Z',
      ),
      '2026-10-08': const AttendanceDay(
        status: 'P',
        inTime: '2026-10-08T11:00:00.000Z',
      ),
    };
    final open = openCheckIn(days, '2026-10-08T12:00:00.000Z');
    expect(open?.date, '2026-10-08');
    expect(
      openCheckIn(
        {
          '2026-10-07': const AttendanceDay(
            status: 'P',
            inTime: '2026-10-07T10:00:00.000Z',
          ),
        },
        '2026-10-08T10:00:00.000Z',
      ),
      isNull,
    );
    expect(
      openCheckIn(
        {
          '2026-10-08': const AttendanceDay(
            status: 'P',
            inTime: '2026-10-08T13:00:00.000Z',
          ),
        },
        '2026-10-08T12:00:00.000Z',
      ),
      isNull,
    );
    expect(
      openCheckIn(
        {
          '2026-09-30': const AttendanceDay(
            status: 'P',
            inTime: '2026-09-30T18:00:00.000Z',
          ),
        },
        '2026-10-01T08:00:00.000Z',
      )?.date,
      '2026-09-30',
    );
  });
}
