import 'package:app/features/branches/domain/branch.dart';
import 'package:app/features/branches/domain/branch_assignment.dart';
import 'package:app/features/branches/domain/branch_form_validation.dart';
import 'package:flutter_test/flutter_test.dart';

const _branchJson = <String, Object?>{
  'id': 'branch-1',
  'name': 'Chennai Office',
  'state': 'Tamil Nadu',
  'lat': 13.08,
  'lng': 80.27,
  'radiusMeters': 150,
  'status': 'active',
  'createdAt': '2026-10-07T00:00:00.000Z',
  'updatedAt': '2026-10-07T00:00:00.000Z',
};

void main() {
  test('parses absent, null, and empty branch addresses', () {
    expect(Branch.fromJson(_branchJson).address, isNull);
    expect(Branch.fromJson({..._branchJson, 'address': null}).address, isNull);
    expect(Branch.fromJson({..._branchJson, 'address': ''}).address, '');
  });

  test('validates latitude, longitude and integer radius bounds', () {
    expect(validateLatitude('-90'), isNull);
    expect(validateLatitude('90.01'), isNotNull);
    expect(validateLatitude('NaN'), isNotNull);
    expect(validateLongitude('-180'), isNull);
    expect(validateLongitude('180.1'), isNotNull);
    expect(validateRadius('20'), isNull);
    expect(validateRadius('1000'), isNull);
    expect(validateRadius('19'), isNotNull);
    expect(validateRadius('20.5'), isNotNull);
  });

  test('primary selection adds it and clearing preserves allowed selection', () {
    final first = const BranchAssignment(
      primaryBranchId: null,
      allowedBranchIds: {},
    ).selectPrimary('branch-1');
    expect(first.allowedBranchIds, {'branch-1'});

    final second = first.selectPrimary(null);
    expect(second.primaryBranchId, isNull);
    expect(second.allowedBranchIds, {'branch-1'});
    expect(second.toggleAllowed('branch-1', false).allowedBranchIds, isEmpty);
  });

  test('primary branch cannot be unchecked from allowed branches', () {
    final assignment = BranchAssignment(
      primaryBranchId: 'branch-1',
      allowedBranchIds: {'branch-1'},
    );
    expect(
      assignment.toggleAllowed('branch-1', false).allowedBranchIds,
      {'branch-1'},
    );
  });
}
