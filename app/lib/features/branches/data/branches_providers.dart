import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/auth_providers.dart';
import '../domain/branch.dart';
import 'branch_repository.dart';

final branchRepositoryProvider = Provider<BranchRepository>(
  (ref) => ApiBranchRepository(ref.watch(apiClientProvider)),
);

final branchesProvider = FutureProvider.family<List<Branch>, String>(
  (ref, status) =>
      ref.watch(branchRepositoryProvider).listBranches(status: status),
  retry: (_, _) => null,
);

final branchProvider = FutureProvider.family<Branch, String>(
  (ref, id) => ref.watch(branchRepositoryProvider).getBranch(id),
  retry: (_, _) => null,
);
