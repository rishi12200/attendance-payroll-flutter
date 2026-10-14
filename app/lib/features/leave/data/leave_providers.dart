import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/auth_providers.dart';
import '../domain/leave_request.dart';
import '../domain/leave_type.dart';
import 'leave_repository.dart';

final leaveRepositoryProvider = Provider<LeaveRepository>(
  (ref) => ApiLeaveRepository(ref.watch(apiClientProvider)),
);

final myLeaveRequestsProvider =
    FutureProvider.family<List<LeaveRequest>, String>((ref, status) {
      ref.watch(signedInUidProvider);
      return ref.watch(leaveRepositoryProvider).myRequests(status);
    }, retry: (_, _) => null);

final adminLeaveRequestsProvider =
    FutureProvider.family<List<LeaveRequest>, ({String status, String? empId})>(
      (ref, filter) {
        ref.watch(signedInUidProvider);
        return ref
            .watch(leaveRepositoryProvider)
            .adminList(filter.status, empId: filter.empId);
      },
      retry: (_, _) => null,
    );

final pendingLeaveCountProvider = FutureProvider<int>((ref) {
  ref.watch(signedInUidProvider);
  return ref
      .watch(leaveRepositoryProvider)
      .adminList('pending')
      .then((requests) => requests.length);
}, retry: (_, _) => null);

final leaveTypesProvider = FutureProvider.family<List<LeaveType>, String>((
  ref,
  status,
) {
  ref.watch(signedInUidProvider);
  return ref.watch(leaveRepositoryProvider).listLeaveTypes(status: status);
}, retry: (_, _) => null);

final leaveBalanceProvider =
    FutureProvider.family<LeaveBalance, ({int? year, String? empId})>((
      ref,
      query,
    ) {
      ref.watch(signedInUidProvider);
      return ref
          .watch(leaveRepositoryProvider)
          .getBalance(year: query.year, empId: query.empId);
    }, retry: (_, _) => null);
