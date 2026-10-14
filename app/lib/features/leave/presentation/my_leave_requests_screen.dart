import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/api/app_exception.dart';
import '../data/leave_providers.dart';
import '../domain/leave_helpers.dart';
import '../domain/leave_request.dart';
import '../domain/leave_type.dart';
import '../domain/remaining_leave_slices.dart';
import 'employee_holidays_section.dart';
import 'remaining_leave_chart.dart';

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
  int _section = 0;

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
      ref.invalidate(leaveBalanceProvider);
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
    return Scaffold(
      appBar: AppBar(title: const Text('My leave')),
      floatingActionButton: _section == 0
          ? FloatingActionButton.extended(
              key: const ValueKey('apply-leave-button'),
              onPressed: () => context.push('/employee/leave/apply'),
              icon: const Icon(Icons.add),
              label: const Text('Apply for leave'),
            )
          : null,
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: SegmentedButton<int>(
              segments: const [
                ButtonSegment(value: 0, label: Text('Requests')),
                ButtonSegment(value: 1, label: Text('Balance')),
                ButtonSegment(value: 2, label: Text('Holidays')),
              ],
              selected: {_section},
              onSelectionChanged: (selection) =>
                  setState(() => _section = selection.first),
            ),
          ),
          if (_section == 0)
            Expanded(child: _requestsPane())
          else if (_section == 1)
            const Expanded(child: _BalancePane())
          else
            const Expanded(child: EmployeeHolidaysSection()),
        ],
      ),
    );
  }

  Widget _requestsPane() {
    final requests = ref.watch(myLeaveRequestsProvider(_status));
    return Column(
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
                      itemBuilder: (context, index) => LeaveRequestCard(
                        request: items[index],
                        onCancel: () => _cancel(items[index]),
                        onTap: () => showLeaveDetails(context, items[index]),
                      ),
                    ),
            ),
          ),
        ),
      ],
    );
  }
}

class LeaveRequestCard extends StatelessWidget {
  const LeaveRequestCard({
    required this.request,
    required this.onCancel,
    required this.onTap,
    this.showCancel = true,
    super.key,
  });
  final LeaveRequest request;
  final VoidCallback onCancel;
  final VoidCallback onTap;
  final bool showCancel;

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
                LeaveStatusChip(status: request.status),
              ],
            ),
            Text(
              pluralDays(
                request.requestedDays ??
                    leaveDayCount(request.fromDate, request.toDate).toDouble(),
              ),
            ),
            Text(
              '${leaveTypeDisplayName(name: request.leaveTypeName, id: request.leaveTypeId)} · ${sessionLabel(request.session)}',
            ),
            if (request.paid != null)
              Chip(label: Text(paidLabel(request.paid!))),
            const SizedBox(height: 8),
            Text(request.reason),
            if (request.status == LeaveStatus.approved) ...[
              const SizedBox(height: 8),
              Text(
                '${pluralDays(request.writtenDays ?? request.writtenDates.length.toDouble())} applied, ${request.skippedDates.length} skipped',
              ),
            ] else if (request.status == LeaveStatus.rejected &&
                (request.decisionNote ?? '').isNotEmpty) ...[
              const SizedBox(height: 8),
              Text('Admin note: ${request.decisionNote}'),
            ],
            if (request.status != LeaveStatus.pending &&
                request.status != LeaveStatus.rejected &&
                (request.decisionNote ?? '').isNotEmpty)
              Text('Admin note: ${request.decisionNote}'),
            if (showCancel && request.status == LeaveStatus.pending)
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

class LeaveStatusChip extends StatelessWidget {
  const LeaveStatusChip({required this.status, super.key});
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

void showLeaveDetails(
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
            '${pluralDays(request.requestedDays ?? leaveDayCount(request.fromDate, request.toDate).toDouble())} · ${request.reason}',
          ),
          Text(
            '${leaveTypeDisplayName(name: request.leaveTypeName, id: request.leaveTypeId)} · ${sessionLabel(request.session)}',
          ),
          if (request.paid != null) Text(paidLabel(request.paid!)),
          Text('Status: ${request.status.name}'),
          if (request.decidedAt != null)
            Text('Decision date: ${request.decidedAt!.split('T').first}'),
          if ((request.decisionNote ?? '').isNotEmpty)
            Text('Admin note: ${request.decisionNote}'),
          if (request.writtenDates.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text(
              'Days applied (${formatDays(request.writtenDays ?? request.writtenDates.length.toDouble())})',
            ),
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

class _BalancePane extends ConsumerStatefulWidget {
  const _BalancePane();
  @override
  ConsumerState<_BalancePane> createState() => _BalancePaneState();
}

class _BalancePaneState extends ConsumerState<_BalancePane> {
  int? _year;
  int? _anchorYear;

  Future<void> _refresh() async {
    final key = (year: _year, empId: null);
    ref.invalidate(leaveBalanceProvider(key));
    ref.invalidate(leaveTypesProvider('active'));
    await ref.read(leaveBalanceProvider(key).future);
  }

  @override
  Widget build(BuildContext context) {
    final key = (year: _year, empId: null);
    final balance = ref.watch(leaveBalanceProvider(key));
    final activeTypes = ref.watch(leaveTypesProvider('active'));
    return balance.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => ListView(
        children: [
          const SizedBox(height: 120),
          Center(
            child: Text(
              error is AppException
                  ? error.message
                  : 'Could not load balances.',
            ),
          ),
          Center(
            child: TextButton(
              onPressed: () => ref.invalidate(leaveBalanceProvider(key)),
              child: const Text('Retry'),
            ),
          ),
        ],
      ),
      data: (value) {
        final activeTypeIds = activeTypes.asData?.value
            .map((type) => type.id)
            .toSet();
        final chartData = buildRemainingSlices(
          balanceTypes: value.types,
          activeTypeIds: activeTypeIds,
        );
        _anchorYear ??= value.year;
        _year ??= value.year;
        return RefreshIndicator(
          onRefresh: _refresh,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Row(
                children: [
                  IconButton(
                    tooltip: 'Previous leave year',
                    onPressed: _year! > _anchorYear! - 1
                        ? () => setState(() => _year = _year! - 1)
                        : null,
                    icon: const Icon(Icons.chevron_left),
                  ),
                  Expanded(
                    child: Text(
                      value.label,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Next leave year',
                    onPressed: _year! < _anchorYear! + 1
                        ? () => setState(() => _year = _year! + 1)
                        : null,
                    icon: const Icon(Icons.chevron_right),
                  ),
                ],
              ),
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Text('Pending requests are reserved from your balance.'),
              ),
              RemainingLeaveChartCard(balance: value, sliceData: chartData),
              if (value.types.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 48),
                  child: Center(child: Text('No leave balances to show.')),
                ),
              for (final item in value.types) LeaveBalanceCard(item: item),
            ],
          ),
        );
      },
    );
  }
}

class LeaveBalanceCard extends StatelessWidget {
  const LeaveBalanceCard({required this.item, super.key});
  final BalanceType item;
  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '${item.name} (${item.code})',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              Chip(label: Text(paidLabel(item.paid))),
            ],
          ),
          Text(
            'Quota: ${item.quota == null ? 'No limit' : pluralDays(item.quota!)}',
          ),
          Text('Used: ${pluralDays(item.used)}'),
          Text('Pending: ${pluralDays(item.pending)}'),
          Text(
            'Remaining: ${item.remaining == null ? 'No limit' : pluralDays(item.remaining!)}',
          ),
        ],
      ),
    ),
  );
}

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
