import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/auth_providers.dart';
import '../domain/leave_request.dart';
import 'leave_repository.dart';

final leaveRepositoryProvider = Provider<LeaveRepository>(
  (ref) => ApiLeaveRepository(ref.watch(apiClientProvider)),
);

final myLeaveRequestsProvider = FutureProvider.family<List<LeaveRequest>, String>(
  (ref, status) {
    ref.watch(signedInUidProvider);
    return ref.watch(leaveRepositoryProvider).myRequests(status);
  },
  retry: (_, _) => null,
);

final adminLeaveRequestsProvider =
    FutureProvider.family<List<LeaveRequest>, ({String status, String? empId})>(
      (ref, filter) {
        ref.watch(signedInUidProvider);
        return ref.watch(leaveRepositoryProvider).adminList(
          filter.status,
          empId: filter.empId,
        );
      },
      retry: (_, _) => null,
    );

final pendingLeaveCountProvider = FutureProvider<int>((ref) {
  ref.watch(signedInUidProvider);
  return ref.watch(leaveRepositoryProvider).adminList('pending').then(
    (requests) => requests.length,
  );
}, retry: (_, _) => null);
