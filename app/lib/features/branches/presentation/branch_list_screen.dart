import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/api/app_exception.dart';
import '../data/branches_providers.dart';
import '../domain/branch.dart';

class BranchListScreen extends ConsumerStatefulWidget {
  const BranchListScreen({super.key});

  @override
  ConsumerState<BranchListScreen> createState() => _BranchListScreenState();
}

class _BranchListScreenState extends ConsumerState<BranchListScreen> {
  final _search = TextEditingController();
  String _status = 'active';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    ref.invalidate(branchesProvider(_status));
    await ref.read(branchesProvider(_status).future);
  }

  Future<void> _open(String path) async {
    final changed = await context.push<bool>(path);
    if (changed == true && mounted) {
      ref.invalidate(branchesProvider('active'));
      ref.invalidate(branchesProvider('inactive'));
      ref.invalidate(branchesProvider('all'));
    }
  }
  @override
  Widget build(BuildContext context) {
    final state = ref.watch(branchesProvider(_status));
    return Scaffold(
      appBar: AppBar(title: const Text('Branches')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _open('/admin/branches/new'),
        icon: const Icon(Icons.add_location_alt_outlined),
        label: const Text('Add branch'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: TextField(
              controller: _search,
              decoration: const InputDecoration(
                labelText: 'Search branches',
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: (_) => setState(() {}),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: DropdownButtonFormField<String>(
              initialValue: _status,
              decoration: const InputDecoration(labelText: 'Status'),
              items: const [
                DropdownMenuItem(value: 'active', child: Text('Active')),
                DropdownMenuItem(value: 'inactive', child: Text('Inactive')),
                DropdownMenuItem(value: 'all', child: Text('All')),
              ],
              onChanged: (value) {
                if (value != null) setState(() => _status = value);
              },
            ),
          ),
          Expanded(
            child: state.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, _) => _LoadError(
                message: error is AppException
                    ? error.message
                    : 'Could not load branches. Please try again.',
                onRetry: () => ref.invalidate(branchesProvider(_status)),
              ),
              data: (items) {
                final search = _search.text.trim().toLowerCase();
                final filtered = items
                    .where(
                      (branch) =>
                          branch.name.toLowerCase().contains(search) ||
                          branch.state.toLowerCase().contains(search),
                    )
                    .toList(growable: false);
                return RefreshIndicator(
                  onRefresh: _refresh,
                  child: filtered.isEmpty
                      ? ListView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          children: const [
                            SizedBox(height: 140),
                            Center(child: Text('No branches found.')),
                          ],
                        )
                      : ListView.separated(
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 88),
                          itemCount: filtered.length,
                          separatorBuilder: (_, _) =>
                              const SizedBox(height: 8),
                          itemBuilder: (context, index) => _BranchTile(
                            branch: filtered[index],
                            onTap: () =>
                                _open('/admin/branches/${filtered[index].id}'),
                          ),
                        ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _BranchTile extends StatelessWidget {
  const _BranchTile({required this.branch, required this.onTap});

  final Branch branch;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Card(
    child: ListTile(
      leading: const Icon(Icons.location_on_outlined),
      title: Text(branch.name),
      subtitle: Text('${branch.state} · ${branch.radiusMeters} m radius'),
      trailing: branch.status == BranchStatus.inactive
          ? const Chip(label: Text('Inactive'))
          : null,
      onTap: onTap,
    ),
  );
}

class _LoadError extends StatelessWidget {
  const _LoadError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(message, textAlign: TextAlign.center),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh),
            label: const Text('Retry'),
          ),
        ],
      ),
    ),
  );
}
