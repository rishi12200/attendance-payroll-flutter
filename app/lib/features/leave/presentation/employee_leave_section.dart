import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../attendance/data/attendance_views_providers.dart';
import '../../attendance/domain/attendance_views.dart';
import '../../branches/data/branches_providers.dart';
import '../../employees/domain/employee.dart';
import '../data/leave_providers.dart';
import '../domain/leave_request.dart';
import '../domain/leave_type.dart';
import 'admin_leave_requests_screen.dart';
import 'my_leave_requests_screen.dart';

const _statuses = <String, String>{
  'All': 'all',
  'Approved': 'approved',
  'Pending': 'pending',
  'Rejected': 'rejected',
  'Cancelled': 'cancelled',
};

class EmployeeLeaveSection extends ConsumerStatefulWidget {
  const EmployeeLeaveSection({required this.employee, super.key});
  final Employee employee;

  @override
  ConsumerState<EmployeeLeaveSection> createState() =>
      _EmployeeLeaveSectionState();
}

class _EmployeeLeaveSectionState extends ConsumerState<EmployeeLeaveSection> {
  int? _year;
  int? _anchorYear;
  int? _holidayYear;
  bool _holidayYearChosen = false;
  String _status = 'all';

  ({int? year, String? empId}) get _balanceKey =>
      (year: _year, empId: widget.employee.uid);
  ({String status, String? empId}) get _historyKey =>
      (status: _status, empId: widget.employee.uid);

  Future<void> _refresh() async {
    ref.invalidate(leaveBalanceProvider(_balanceKey));
    ref.invalidate(adminLeaveRequestsProvider(_historyKey));
    final branchId = widget.employee.primaryBranchId;
    if (branchId != null && _holidayYear != null) {
      ref.invalidate(
        adminAttendanceHolidaysProvider((
          year: '$_holidayYear',
          branchId: branchId,
        )),
      );
    }
    await Future.wait([
      ref.read(leaveBalanceProvider(_balanceKey).future).then<void>((_) {}),
      ref
          .read(adminLeaveRequestsProvider(_historyKey).future)
          .then<void>((_) {}),
      if (branchId != null && _holidayYear != null)
        ref
            .read(
              adminAttendanceHolidaysProvider((
                year: '$_holidayYear',
                branchId: branchId,
              )).future,
            )
            .then<void>((_) {}),
    ]);
  }

  Future<void> _openRequest(LeaveRequest request) async {
    if (request.status != LeaveStatus.pending) {
      showLeaveDetails(context, request);
      return;
    }
    final changed = await showAdminLeaveDecisionSheet(context, request);
    if (changed == true && mounted) {
      ref.invalidate(adminLeaveRequestsProvider(_historyKey));
      ref.invalidate(leaveBalanceProvider(_balanceKey));
    }
  }

  @override
  Widget build(BuildContext context) {
    final balance = ref.watch(leaveBalanceProvider(_balanceKey));
    final history = ref.watch(adminLeaveRequestsProvider(_historyKey));
    final serverToday = ref.watch(attendanceServerTodayProvider).asData?.value;
    final branchId = widget.employee.primaryBranchId;
    final branches = ref.watch(branchesProvider('active')).asData?.value ?? [];
    final branchName = branches
        .where((branch) => branch.id == branchId)
        .map((branch) => branch.name)
        .firstOrNull;
    final currentBalance = balance.asData?.value;
    if (currentBalance != null) {
      final value = currentBalance;
      _anchorYear ??= value.year;
      _year ??= value.year;
      if (!_holidayYearChosen) {
        _holidayYear = int.tryParse(value.today.substring(0, 4)) ?? value.year;
      }
    } else if (!_holidayYearChosen &&
        _holidayYear == null &&
        serverToday != null) {
      _holidayYear = int.tryParse(serverToday.substring(0, 4));
    }
    final holidayYear = _holidayYear ?? _year;
    final holidays = branchId == null || holidayYear == null
        ? null
        : ref.watch(
            adminAttendanceHolidaysProvider((
              year: '$holidayYear',
              branchId: branchId,
            )),
          );

    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView(
        key: const ValueKey('employee-leave-scroll'),
        padding: const EdgeInsets.all(16),
        children: [
          _balanceBlock(balance),
          const SizedBox(height: 20),
          Text('Leave history', style: Theme.of(context).textTheme.titleLarge),
          Wrap(
            spacing: 6,
            children: _statuses.entries
                .map(
                  (entry) => ChoiceChip(
                    label: Text(entry.key),
                    selected: _status == entry.value,
                    onSelected: (_) => setState(() => _status = entry.value),
                  ),
                )
                .toList(),
          ),
          history.when(
            loading: () => const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (error, _) => _BlockError(
              message: 'Could not load leave requests.',
              onRetry: () =>
                  ref.invalidate(adminLeaveRequestsProvider(_historyKey)),
            ),
            data: (requests) => Column(
              children: [
                if (requests.length == 200)
                  const Padding(
                    padding: EdgeInsets.all(8),
                    child: Text('Showing the latest 200 requests'),
                  ),
                if (requests.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Text('No leave requests'),
                  ),
                for (final request in requests)
                  LeaveRequestCard(
                    request: request,
                    showCancel: false,
                    onCancel: () {},
                    onTap: () => _openRequest(request),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () => context.push(
              '/admin/attendance/employee/${Uri.encodeComponent(widget.employee.uid)}',
            ),
            icon: const Icon(Icons.calendar_month),
            label: const Text('View attendance calendar'),
          ),
          const SizedBox(height: 20),
          Text(
            'Holidays for ${branchName ?? 'their branch'}',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          if (branchId == null)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Text(
                'No primary branch is assigned, so only company-wide holidays apply. See the Holidays screen.',
              ),
            )
          else ...[
            Row(
              children: [
                IconButton(
                  tooltip: 'Previous holiday year',
                  onPressed: holidayYear == null
                      ? null
                      : () => setState(() {
                          _holidayYearChosen = true;
                          _holidayYear = holidayYear - 1;
                        }),
                  icon: const Icon(Icons.chevron_left),
                ),
                Text('$holidayYear'),
                IconButton(
                  tooltip: 'Next holiday year',
                  onPressed: holidayYear == null
                      ? null
                      : () => setState(() {
                          _holidayYearChosen = true;
                          _holidayYear = holidayYear + 1;
                        }),
                  icon: const Icon(Icons.chevron_right),
                ),
              ],
            ),
            if (holidays != null)
              holidays.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (error, _) => _BlockError(
                  message: 'Could not load holidays.',
                  onRetry: () => ref.invalidate(
                    adminAttendanceHolidaysProvider((
                      year: '$holidayYear',
                      branchId: branchId,
                    )),
                  ),
                ),
                data: (items) => items.isEmpty
                    ? const Padding(
                        padding: EdgeInsets.all(12),
                        child: Text('No holidays'),
                      )
                    : Column(
                        children: items
                            .map((holiday) => _HolidayTile(holiday: holiday))
                            .toList(),
                      ),
              ),
          ],
        ],
      ),
    );
  }

  Widget _balanceBlock(AsyncValue<LeaveBalance> balance) => balance.when(
    loading: () => const Padding(
      padding: EdgeInsets.all(24),
      child: Center(child: CircularProgressIndicator()),
    ),
    error: (error, _) => _BlockError(
      message: 'Could not load leave balances.',
      onRetry: () => ref.invalidate(leaveBalanceProvider(_balanceKey)),
    ),
    data: (value) => Column(
      children: [
        Row(
          children: [
            IconButton(
              tooltip: 'Previous leave year',
              onPressed: _year! > _anchorYear! - 1
                  ? () => setState(() {
                      _year = _year! - 1;
                    })
                  : null,
              icon: const Icon(Icons.chevron_left),
            ),
            Expanded(child: Text(value.label, textAlign: TextAlign.center)),
            IconButton(
              tooltip: 'Next leave year',
              onPressed: _year! < _anchorYear! + 1
                  ? () => setState(() {
                      _year = _year! + 1;
                    })
                  : null,
              icon: const Icon(Icons.chevron_right),
            ),
          ],
        ),
        const Align(
          alignment: Alignment.centerLeft,
          child: Text('Pending requests are reserved from the balance.'),
        ),
        if (value.types.isEmpty)
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text('No leave balances to show.'),
          ),
        for (final type in value.types) LeaveBalanceCard(item: type),
      ],
    ),
  );
}

class _HolidayTile extends StatelessWidget {
  const _HolidayTile({required this.holiday});
  final AttendanceHoliday holiday;

  @override
  Widget build(BuildContext context) {
    final date = DateTime.tryParse(holiday.date);
    const weekdays = [
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
      'Sunday',
    ];
    final weekday =
        holiday.weekday ?? (date == null ? '' : weekdays[date.weekday - 1]);
    return Card(
      child: ListTile(
        title: Text(holiday.date),
        subtitle: Text('$weekday · ${holiday.name}'),
      ),
    );
  }
}

class _BlockError extends StatelessWidget {
  const _BlockError({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(12),
    child: Column(
      children: [
        Text(message),
        TextButton(onPressed: onRetry, child: const Text('Retry')),
      ],
    ),
  );
}
