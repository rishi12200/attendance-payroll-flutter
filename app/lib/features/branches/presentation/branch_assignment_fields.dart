import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/app_exception.dart';
import '../data/branches_providers.dart';
import '../domain/branch.dart';
import '../domain/branch_assignment.dart';

class BranchAssignmentFields extends ConsumerWidget {
  const BranchAssignmentFields({
    required this.assignment,
    required this.onChanged,
    super.key,
  });

  final BranchAssignment assignment;
  final ValueChanged<BranchAssignment> onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final branches = ref.watch(branchesProvider('active'));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Branch assignment',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        branches.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                error is AppException
                    ? error.message
                    : 'Could not load branches.',
              ),
              TextButton.icon(
                onPressed: () => ref.invalidate(branchesProvider('active')),
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
              ),
            ],
          ),
          data: (items) => _BranchAssignmentControls(
            branches: items,
            assignment: assignment,
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }
}

class _BranchAssignmentControls extends StatelessWidget {
  const _BranchAssignmentControls({
    required this.branches,
    required this.assignment,
    required this.onChanged,
  });

  final List<Branch> branches;
  final BranchAssignment assignment;
  final ValueChanged<BranchAssignment> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DropdownButtonFormField<String?>(
          key: ValueKey(
            'primary-${branches.any((branch) => branch.id == assignment.primaryBranchId) ? assignment.primaryBranchId : 'missing'}',
          ),
          initialValue:
              branches.any((branch) => branch.id == assignment.primaryBranchId)
              ? assignment.primaryBranchId
              : null,
          decoration: const InputDecoration(labelText: 'Primary branch'),
          items: [
            const DropdownMenuItem<String?>(
              value: null,
              child: Text('No primary branch'),
            ),
            ...branches.map(
              (branch) => DropdownMenuItem<String?>(
                value: branch.id,
                child: Text(branch.name),
              ),
            ),
          ],
          onChanged: (id) => onChanged(assignment.selectPrimary(id)),
        ),
        const SizedBox(height: 8),
        const Text('Allowed branches'),
        if (branches.isEmpty) const Text('No active branches available.'),
        ...branches.map(
          (branch) => CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(branch.name),
            value: assignment.allowedBranchIds.contains(branch.id),
            onChanged: branch.id == assignment.primaryBranchId
                ? null
                : (selected) => onChanged(
                    assignment.toggleAllowed(branch.id, selected ?? false),
                  ),
          ),
        ),
        if (assignment.primaryBranchId == null &&
            assignment.allowedBranchIds.isEmpty)
          const Text('This employee cannot check in yet.'),
      ],
    );
  }
}
