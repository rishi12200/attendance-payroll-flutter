import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/api/app_exception.dart';
import '../data/leave_providers.dart';
import '../domain/leave_helpers.dart';
import '../domain/leave_request.dart';

const _filters = <String, String>{
  'All': 'all',
  'Pending': 'pending',
  'Approved': 'approved',
  'Rejected': 'rejected',
  'Cancelled': 'cancelled',
};

class MyLeaveRequestsScreen extends ConsumerStatefulWidget {
  const MyLeaveRequestsScreen({super.key});

  @override
  ConsumerState<MyLeaveRequestsScreen> createState() =>
      _MyLeaveRequestsScreenState();
}

class _MyLeaveRequestsScreenState extends ConsumerState<MyLeaveRequestsScreen> {
  String _status = 'all';

  Future<void> _refresh() async {
    ref.invalidate(myLeaveRequestsProvider(_status));
    await ref.read(myLeaveRequestsProvider(_status).future);
  }

  Future<void> _cancel(LeaveRequest request) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cancel leave request?'),
        content: Text(
          'Cancel ${readableLeaveRange(request.fromDate, request.toDate)}?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep request'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Cancel request'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await ref.read(leaveRepositoryProvider).cancel(request.id);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Leave request cancelled.')));
    } on AppException catch (error) {
      if (!mounted) return;
      final message = error.statusCode == 404
          ? 'This leave request could not be found.'
          : error.code == 'NOT_PENDING'
          ? 'This request has already been decided and cannot be cancelled.'
          : error.message;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not cancel the request.')),
        );
      }
    } finally {
      if (mounted) await _refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    final requests = ref.watch(myLeaveRequestsProvider(_status));
    return Scaffold(
      appBar: AppBar(title: const Text('My leave requests')),
      floatingActionButton: FloatingActionButton.extended(
        key: const ValueKey('apply-leave-button'),
        onPressed: () => context.push('/employee/leave/apply'),
        icon: const Icon(Icons.add),
        label: const Text('Apply for leave'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: DropdownButtonFormField<String>(
              key: const ValueKey('my-leave-status-filter'),
              initialValue: _status,
              decoration: const InputDecoration(labelText: 'Status'),
              items: _filters.entries
                  .map(
                    (entry) => DropdownMenuItem(
                      value: entry.value,
                      child: Text(entry.key),
                    ),
                  )
                  .toList(),
              onChanged: (value) => setState(() => _status = value ?? 'all'),
            ),
          ),
          Expanded(
            child: requests.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, _) => _ErrorView(
                error: error,
                onRetry: () => ref.invalidate(myLeaveRequestsProvider(_status)),
              ),
              data: (items) => RefreshIndicator(
                onRefresh: _refresh,
                child: items.isEmpty
                    ? ListView(
                        children: const [
                          SizedBox(height: 160),
                          Center(child: Text('No leave requests yet.')),
                        ],
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(12, 4, 12, 92),
                        itemCount: items.length,
                        itemBuilder: (context, index) => _LeaveCard(
                          request: items[index],
                          onCancel: () => _cancel(items[index]),
                          onTap: () => _showLeaveDetails(context, items[index]),
                        ),
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LeaveCard extends StatelessWidget {
  const _LeaveCard({
    required this.request,
    required this.onCancel,
    required this.onTap,
  });
  final LeaveRequest request;
  final VoidCallback onCancel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Card(
    child: InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    readableLeaveRange(request.fromDate, request.toDate),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                _StatusChip(status: request.status),
              ],
            ),
            Text('${leaveDayCount(request.fromDate, request.toDate)} days'),
            const SizedBox(height: 8),
            Text(request.reason),
            if (request.status == LeaveStatus.approved) ...[
              const SizedBox(height: 8),
              Text(
                request.leaveType == LeaveType.paid
                    ? 'Paid leave'
                    : 'Unpaid leave',
              ),
              Text(
                '${request.writtenDates.length} days applied, ${request.skippedDates.length} skipped',
              ),
              if ((request.decisionNote ?? '').isNotEmpty)
                Text('Admin note: ${request.decisionNote}'),
            ] else if (request.status == LeaveStatus.rejected &&
                (request.decisionNote ?? '').isNotEmpty) ...[
              const SizedBox(height: 8),
              Text('Admin note: ${request.decisionNote}'),
            ],
            if (request.status == LeaveStatus.pending)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: onCancel,
                  icon: const Icon(Icons.cancel_outlined),
                  label: const Text('Cancel'),
                ),
              ),
          ],
        ),
      ),
    ),
  );
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});
  final LeaveStatus status;
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (label, color) = switch (status) {
      LeaveStatus.pending => ('Pending', scheme.tertiaryContainer),
      LeaveStatus.approved => ('Approved', scheme.primaryContainer),
      LeaveStatus.rejected => ('Rejected', scheme.errorContainer),
      LeaveStatus.cancelled => ('Cancelled', scheme.surfaceContainerHighest),
    };
    return Chip(label: Text(label), backgroundColor: color);
  }
}

void _showLeaveDetails(
  BuildContext context,
  LeaveRequest request,
) => showModalBottomSheet<void>(
  context: context,
  showDragHandle: true,
  builder: (context) => SafeArea(
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: ListView(
        shrinkWrap: true,
        children: [
          Text(
            readableLeaveRange(request.fromDate, request.toDate),
            style: Theme.of(context).textTheme.titleLarge,
          ),
          Text(
            '${leaveDayCount(request.fromDate, request.toDate)} days · ${request.reason}',
          ),
          Text('Status: ${request.status.name}'),
          if (request.writtenDates.isNotEmpty) ...[
            const SizedBox(height: 16),
            const Text('Days applied'),
            ...request.writtenDates.map(
              (date) => ListTile(
                dense: true,
                leading: const Icon(Icons.check),
                title: Text(date),
              ),
            ),
          ],
          if (request.skippedDates.isNotEmpty) ...[
            const SizedBox(height: 8),
            const Text('Days skipped'),
            ...request.skippedDates.map(
              (item) => ListTile(
                dense: true,
                leading: const Icon(Icons.skip_next),
                title: Text(item.date),
                subtitle: Text(skippedReasonLabel(item.reason)),
              ),
            ),
          ],
          if (request.skippedDates.isEmpty && request.writtenDates.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 18),
              child: Text('Decision details are not available yet.'),
            ),
        ],
      ),
    ),
  ),
);

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.error, required this.onRetry});
  final Object error;
  final VoidCallback onRetry;
  @override
  Widget build(BuildContext context) => ListView(
    children: [
      const SizedBox(height: 120),
      Center(
        child: Text(
          error is AppException
              ? (error as AppException).message
              : 'Could not load leave requests.',
        ),
      ),
      Center(
        child: TextButton(onPressed: onRetry, child: const Text('Retry')),
      ),
    ],
  );
}
