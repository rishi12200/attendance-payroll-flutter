import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/leave_providers.dart';

class PendingLeaveBadge extends ConsumerWidget {
  const PendingLeaveBadge({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) => ref
      .watch(pendingLeaveCountProvider)
      .when(
        data: (count) => count == 0
            ? const Icon(Icons.chevron_right)
            : Badge(
                label: Text('$count'),
                child: const Icon(Icons.chevron_right),
              ),
        loading: () => const SizedBox.square(
          dimension: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
        error: (_, _) => const Icon(Icons.chevron_right),
      );
}
