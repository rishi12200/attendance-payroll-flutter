import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/app_exception.dart';
import '../data/leave_providers.dart';
import '../domain/leave_helpers.dart';
import '../domain/leave_request.dart';
import '../domain/leave_type.dart';

class AdminLeaveRequestsScreen extends ConsumerStatefulWidget {
  const AdminLeaveRequestsScreen({super.key});
  @override
  ConsumerState<AdminLeaveRequestsScreen> createState() =>
      _AdminLeaveRequestsScreenState();
}

class _AdminLeaveRequestsScreenState
    extends ConsumerState<AdminLeaveRequestsScreen> {
  String _status = 'pending';
  String _search = '';
  ({String status, String? empId}) get _filter =>
      (status: _status, empId: null);

  Future<void> _refresh() async {
    ref.invalidate(adminLeaveRequestsProvider(_filter));
    ref.invalidate(pendingLeaveCountProvider);
    await ref.read(adminLeaveRequestsProvider(_filter).future);
  }

  Future<void> _open(LeaveRequest request) async {
    final changed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _LeaveDecisionSheet(request: request),
    );
    if (changed == true && mounted) await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final requests = ref.watch(adminLeaveRequestsProvider(_filter));
    return Scaffold(
      appBar: AppBar(title: const Text('Leave requests')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: DropdownButtonFormField<String>(
              key: const ValueKey('admin-leave-status-filter'),
              initialValue: _status,
              decoration: const InputDecoration(labelText: 'Status'),
              items: const [
                DropdownMenuItem(value: 'pending', child: Text('Pending')),
                DropdownMenuItem(value: 'approved', child: Text('Approved')),
                DropdownMenuItem(value: 'rejected', child: Text('Rejected')),
                DropdownMenuItem(value: 'cancelled', child: Text('Cancelled')),
                DropdownMenuItem(value: 'all', child: Text('All')),
              ],
              onChanged: (value) =>
                  setState(() => _status = value ?? 'pending'),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: TextField(
              key: const ValueKey('admin-leave-search'),
              decoration: const InputDecoration(
                labelText: 'Search name or employee code',
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: (value) =>
                  setState(() => _search = value.trim().toLowerCase()),
            ),
          ),
          Expanded(
            child: requests.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, _) => _AdminError(
                error: error,
                retry: () =>
                    ref.invalidate(adminLeaveRequestsProvider(_filter)),
              ),
              data: (all) {
                final filtered = all
                    .where(
                      (item) =>
                          (item.name ?? '').toLowerCase().contains(_search) ||
                          (item.empCode ?? '').toLowerCase().contains(_search),
                    )
                    .toList(growable: false);
                return RefreshIndicator(
                  onRefresh: _refresh,
                  child: filtered.isEmpty
                      ? ListView(
                          children: const [
                            SizedBox(height: 160),
                            Center(child: Text('No matching leave requests.')),
                          ],
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.fromLTRB(12, 4, 12, 20),
                          itemCount: filtered.length,
                          itemBuilder: (context, index) => _AdminLeaveCard(
                            request: filtered[index],
                            onTap: () => _open(filtered[index]),
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

class _AdminLeaveCard extends StatelessWidget {
  const _AdminLeaveCard({required this.request, required this.onTap});
  final LeaveRequest request;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Card(
    child: ListTile(
      onTap: onTap,
      title: Text(
        request.name?.isNotEmpty == true ? request.name! : 'Employee',
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${request.empCode ?? ''} · ${readableLeaveRange(request.fromDate, request.toDate)}',
          ),
          Text(
            '${leaveTypeDisplayName(name: request.leaveTypeName, id: request.leaveTypeId)} · ${sessionLabel(request.session)} · ${pluralDays(request.requestedDays ?? leaveDayCount(request.fromDate, request.toDate).toDouble())} · ${request.reason}',
          ),
        ],
      ),
      trailing: _AdminStatus(status: request.status),
    ),
  );
}

class _AdminStatus extends StatelessWidget {
  const _AdminStatus({required this.status});
  final LeaveStatus status;
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final color = switch (status) {
      LeaveStatus.pending => colors.tertiaryContainer,
      LeaveStatus.approved => colors.primaryContainer,
      LeaveStatus.rejected => colors.errorContainer,
      LeaveStatus.cancelled => colors.surfaceContainerHighest,
    };
    return Chip(
      label: Text(status.name[0].toUpperCase() + status.name.substring(1)),
      backgroundColor: color,
    );
  }
}

class _LeaveDecisionSheet extends ConsumerStatefulWidget {
  const _LeaveDecisionSheet({required this.request});
  final LeaveRequest request;
  @override
  ConsumerState<_LeaveDecisionSheet> createState() =>
      _LeaveDecisionSheetState();
}

class _LeaveDecisionSheetState extends ConsumerState<_LeaveDecisionSheet> {
  final _note = TextEditingController();
  bool _submitting = false;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _decide(String decision) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          decision == 'approved' ? 'Confirm approval' : 'Confirm rejection',
        ),
        content: Text(
          decision == 'approved'
              ? 'Approve this leave request?'
              : 'Reject this leave request?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Go back'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _submitting = true);
    try {
      final result = await ref
          .read(leaveRepositoryProvider)
          .decide(
            id: widget.request.id,
            decision: decision,
            note: _note.text.trim().isEmpty ? null : _note.text.trim(),
          );
      ref.invalidate(
        adminLeaveRequestsProvider((status: 'pending', empId: null)),
      );
      ref.invalidate(pendingLeaveCountProvider);
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(
            decision == 'approved' ? 'Leave approved' : 'Leave rejected',
          ),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView(
              shrinkWrap: true,
              children: [
                if (result.noDaysWritten)
                  const Text(
                    'No days were written. Every date in the range was skipped.',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                if (decision == 'approved')
                  Text(
                    '${pluralDays(result.writtenDays ?? result.writtenDates.length.toDouble())} written.',
                  ),
                if (result.writtenDates.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  const Text('Days written'),
                  ...result.writtenDates.map(Text.new),
                ],
                if (result.skippedDates.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  const Text('Days skipped'),
                  ...result.skippedDates.map(
                    (item) => Text(
                      '${item.date}: ${skippedReasonLabel(item.reason)}',
                    ),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Done'),
            ),
          ],
        ),
      );
      if (mounted) Navigator.pop(context, true);
    } on AppException catch (error) {
      if (!mounted) return;
      final message = switch (error.code) {
        'ALREADY_DECIDED' => 'Someone already decided this request.',
        'LEAVE_TYPE_MISSING' => 'This request has no leave type. Reject it or ask the employee to apply again.',
        'MONTH_LOCKED' =>
          'This month is locked, so the leave could not be approved.',
        'QUOTA_EXCEEDED' => _quotaApprovalMessage(error, widget.request),
        _ => error.message,
      };
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
      ref.invalidate(
        adminLeaveRequestsProvider((status: 'pending', empId: null)),
      );
      ref.invalidate(pendingLeaveCountProvider);
      Navigator.pop(context, true);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not update this leave request.')),
        );
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final request = widget.request;
    final pending = request.status == LeaveStatus.pending;
    final balance = ref.watch(
      leaveBalanceProvider((year: null, empId: request.empId)),
    );
    final balanceForDate = balance.asData?.value;
    final dateInBalanceYear =
        balanceForDate != null &&
        request.fromDate.compareTo(balanceForDate.startDate) >= 0 &&
        request.fromDate.compareTo(balanceForDate.endDate) <= 0;
    final balanceType = dateInBalanceYear
        ? balanceForDate.types
              .where((item) => item.leaveTypeId == request.leaveTypeId)
              .firstOrNull
        : null;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          8,
          20,
          MediaQuery.viewInsetsOf(context).bottom + 20,
        ),
        child: ListView(
          shrinkWrap: true,
          children: [
            Text(
              request.name ?? 'Employee',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            Text(
              '${request.empCode ?? ''} · ${readableLeaveRange(request.fromDate, request.toDate)}',
            ),
            Text('Status: ${request.status.name}'),
            Text(
              pluralDays(
                request.requestedDays ??
                    leaveDayCount(request.fromDate, request.toDate).toDouble(),
              ),
            ),
            const SizedBox(height: 10),
            Text(request.reason),
            Text(
              '${leaveTypeDisplayName(name: request.leaveTypeName, id: request.leaveTypeId)} · ${sessionLabel(request.session)}',
            ),
            if (request.paid != null)
              Chip(label: Text(paidLabel(request.paid!))),
            if (pending && request.leaveTypeId == null)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(12),
                  child: Text(
                    'This request was made before leave types existed. Reject it, or ask the employee to apply again.',
                  ),
                ),
              ),
            if (pending && request.leaveTypeId != null) ...[
              if (dateInBalanceYear && balanceType != null)
                Text(
                  'Balance for ${balanceForDate.label}: ${balanceType.remaining == null ? 'No limit' : '${pluralDays(balanceType.remaining!)} left'}',
                )
              else if (balance.hasValue || balance.hasError)
                const Text("The balance for that leave year isn't shown."),
            ],
            if (request.status == LeaveStatus.approved) ...[
              const SizedBox(height: 12),
              Text(
                '${pluralDays(request.writtenDays ?? request.writtenDates.length.toDouble())} applied, ${request.skippedDates.length} skipped',
              ),
            ],
            if ((request.decisionNote ?? '').isNotEmpty)
              Text('Admin note: ${request.decisionNote}'),
            if (request.writtenDates.isNotEmpty) ...[
              const SizedBox(height: 12),
              const Text('Days applied'),
              ...request.writtenDates.map((date) => Text('• $date')),
            ],
            if (request.skippedDates.isNotEmpty) ...[
              const SizedBox(height: 12),
              const Text('Days skipped'),
              ...request.skippedDates.map(
                (item) =>
                    Text('${item.date}: ${skippedReasonLabel(item.reason)}'),
              ),
            ],
            if (pending) ...[
              const SizedBox(height: 18),
              TextField(
                controller: _note,
                maxLength: 200,
                decoration: const InputDecoration(labelText: 'Optional note'),
              ),
              const SizedBox(height: 8),
              FilledButton(
                onPressed: !_submitting && request.leaveTypeId != null
                    ? () => _decide('approved')
                    : null,
                child: _submitting
                    ? const CircularProgressIndicator()
                    : const Text('Approve'),
              ),
              OutlinedButton(
                onPressed: _submitting ? null : () => _decide('rejected'),
                child: const Text('Reject'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

String _quotaApprovalMessage(AppException error, LeaveRequest request) {
  final details = error.details;
  final name = details['leaveTypeName'] ?? request.leaveTypeName;
  final year = details['yearLabel'];
  final remaining = details['remaining'];
  if (name is String && year is String && remaining is num) {
    return 'Approving would exceed $name for $year. Remaining: ${pluralDays(remaining.toDouble())}.';
  }
  return error.message;
}

class _AdminError extends StatelessWidget {
  const _AdminError({required this.error, required this.retry});
  final Object error;
  final VoidCallback retry;
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
        child: TextButton(onPressed: retry, child: const Text('Retry')),
      ),
    ],
  );
}
