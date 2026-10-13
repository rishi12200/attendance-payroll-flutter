import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/app_exception.dart';
import '../../branches/data/branches_providers.dart';
import '../../branches/domain/branch.dart';
import '../data/attendance_views_providers.dart';
import '../domain/attendance_helpers.dart';
import '../domain/attendance_views.dart';
import '../domain/holiday_helpers.dart';

class AdminHolidaysScreen extends ConsumerStatefulWidget {
  const AdminHolidaysScreen({super.key});

  @override
  ConsumerState<AdminHolidaysScreen> createState() =>
      _AdminHolidaysScreenState();
}

class _AdminHolidaysScreenState extends ConsumerState<AdminHolidaysScreen> {
  int? _year;
  String? _branchId;

  @override
  Widget build(BuildContext context) {
    final today = ref.watch(attendanceServerTodayProvider);
    return today.when(
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (error, _) => Scaffold(
        appBar: AppBar(title: const Text('Holidays')),
        body: _HolidayError(
          message: _errorMessage(error),
          onRetry: () => ref.invalidate(attendanceServerTodayProvider),
        ),
      ),
      data: (serverToday) {
        _year ??= int.parse(serverToday.substring(0, 4));
        return _buildScreen(context, serverToday);
      },
    );
  }

  Widget _buildScreen(BuildContext context, String today) {
    final year = _year!;
    final query = (year: '$year', branchId: _branchId);
    final holidays = ref.watch(adminAttendanceHolidaysProvider(query));
    final branches = ref.watch(branchesProvider('active'));
    return Scaffold(
      appBar: AppBar(
        title: const Text('Holidays'),
        actions: [
          IconButton(
            tooltip: 'Choose year',
            onPressed: () => _chooseYear(context, today),
            icon: Text('$year'),
          ),
          IconButton(
            key: const ValueKey('add-holiday'),
            tooltip: 'Add holiday',
            onPressed: () => _addHoliday(context, today),
            icon: const Icon(Icons.add),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => _refresh(query),
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _branchFilter(branches),
            if (_branchId != null)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  key: const ValueKey('clear-holiday-filter'),
                  onPressed: () => setState(() => _branchId = null),
                  icon: const Icon(Icons.filter_alt_off),
                  label: const Text('Clear filter'),
                ),
              ),
            holidays.when(
              loading: () => const SizedBox(
                height: 220,
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (error, _) => _HolidayError(
                message: _errorMessage(error),
                onRetry: () =>
                    ref.invalidate(adminAttendanceHolidaysProvider(query)),
              ),
              data: (items) {
                final sorted = [...items]
                  ..sort((a, b) {
                    final dateOrder = a.date.compareTo(b.date);
                    return dateOrder == 0
                        ? a.name.compareTo(b.name)
                        : dateOrder;
                  });
                if (sorted.isEmpty) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 36),
                    child: Center(child: Text('No holidays for $year')),
                  );
                }
                return Column(
                  children: [
                    for (final holiday in sorted)
                      Card(
                        child: ListTile(
                          onTap: () => _showDetails(holiday),
                          title: Text(holiday.name),
                          subtitle: Text(readableHolidayDate(holiday.date)),
                          trailing: Wrap(
                            crossAxisAlignment: WrapCrossAlignment.center,
                            spacing: 4,
                            children: [
                              Chip(
                                label: Text(adminHolidayScopeLabel(holiday)),
                              ),
                              IconButton(
                                key: ValueKey('delete-holiday-${holiday.id}'),
                                tooltip: 'Delete ${holiday.name}',
                                onPressed: () => _confirmDelete(holiday),
                                icon: const Icon(Icons.delete_outline),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _branchFilter(AsyncValue<List<Branch>> branches) => branches.when(
    loading: () => const LinearProgressIndicator(),
    error: (error, _) => Row(
      children: [
        const Expanded(child: Text('Could not load active branches.')),
        TextButton(
          onPressed: () => ref.invalidate(branchesProvider('active')),
          child: const Text('Retry'),
        ),
      ],
    ),
    data: (items) => DropdownButtonFormField<String>(
      key: const ValueKey('holiday-branch-filter'),
      initialValue: _branchId ?? 'all',
      decoration: const InputDecoration(labelText: 'Branch filter'),
      items: [
        const DropdownMenuItem(value: 'all', child: Text('All holidays')),
        ...items
            .where((branch) => branch.status == BranchStatus.active)
            .map(
              (branch) => DropdownMenuItem(
                value: branch.id,
                child: Text('${branch.name} · ${branch.state}'),
              ),
            ),
      ],
      onChanged: (value) =>
          setState(() => _branchId = value == 'all' ? null : value),
    ),
  );

  Future<void> _refresh(({String year, String? branchId}) query) async {
    ref.invalidate(adminAttendanceHolidaysProvider(query));
    await ref.read(adminAttendanceHolidaysProvider(query).future);
  }

  Future<void> _chooseYear(BuildContext context, String today) async {
    final currentYear = int.parse(today.substring(0, 4));
    final picked = await showDatePicker(
      context: context,
      initialDate: _year == currentYear
          ? _dateTime(today)
          : DateTime.utc(_year!, 1, 1),
      firstDate: DateTime.utc(2000),
      lastDate: DateTime.utc(2100),
      helpText: 'Choose a date in the year',
    );
    if (picked != null && mounted) setState(() => _year = picked.year);
  }

  Future<void> _addHoliday(BuildContext context, String today) async {
    final currentYear = int.parse(today.substring(0, 4));
    final initialDate = _year == currentYear ? today : '$_year-01-01';
    List<Branch> activeBranches;
    try {
      activeBranches = await ref.read(branchesProvider('active').future);
    } catch (_) {
      if (mounted) _showMessage('Could not load branches. Please retry.');
      return;
    }
    if (!context.mounted) return;
    final dialogContext = context;
    final created = await showDialog<AttendanceHoliday>(
      context: dialogContext,
      builder: (_) => _AddHolidayDialog(
        initialDate: _dateTime(initialDate),
        selectedYear: _year!,
        branches: activeBranches
            .where((branch) => branch.status == BranchStatus.active)
            .toList(),
      ),
    );
    if (created == null || !mounted || !dialogContext.mounted) return;
    setState(() => _year = int.parse(created.date.substring(0, 4)));
    _invalidateAttendanceViews(created.date);
    _showMessage('Holiday added.');
  }

  Future<void> _showDetails(AttendanceHoliday holiday) =>
      showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        builder: (context) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: ListView(
              shrinkWrap: true,
              children: [
                Text(
                  holiday.name,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                Text(readableHolidayDate(holiday.date)),
                const SizedBox(height: 12),
                Text('Scope: ${adminHolidayScopeLabel(holiday)}'),
                if (holiday.scope == 'branches') ...[
                  const SizedBox(height: 8),
                  const Text('Branches'),
                  ...holiday.branchNames.map((name) => Text(name)),
                ],
                if (holiday.createdBy != null)
                  Text('Created by: ${holiday.createdBy}'),
                if (holiday.createdAt != null)
                  Text('Created: ${_formatCreatedAt(holiday.createdAt!)}'),
              ],
            ),
          ),
        ),
      );

  Future<void> _confirmDelete(AttendanceHoliday holiday) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete holiday?'),
        content: Text(
          'Delete ${holiday.name} on ${readableHolidayDate(holiday.date)} '
          '(${adminHolidayScopeLabel(holiday)})?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const ValueKey('confirm-delete-holiday'),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ref
          .read(attendanceViewsRepositoryProvider)
          .deleteHoliday(holiday.id);
      if (!mounted) return;
      _invalidateAttendanceViews(holiday.date);
      _showMessage('Holiday deleted.');
    } on AppException catch (error) {
      if (!mounted) return;
      await _refresh((year: holiday.date.substring(0, 4), branchId: _branchId));
      if (error.statusCode == 404) {
        _showMessage(
          'This holiday was already removed. The list was refreshed.',
        );
      } else if (error.code == 'MONTH_LOCKED') {
        _showMessage('That month is locked for payroll.');
      } else {
        _showMessage(error.message);
      }
    }
  }

  void _invalidateAttendanceViews(String date) {
    ref.invalidate(attendanceHolidaysProvider(date.substring(0, 4)));
    ref.invalidate(
      adminAttendanceHolidaysProvider((
        year: date.substring(0, 4),
        branchId: _branchId,
      )),
    );
    ref.invalidate(myAttendanceCalendarProvider);
    ref.invalidate(employeeAttendanceCalendarProvider);
    ref.invalidate(attendanceSummaryProvider);
    ref.invalidate(attendanceByDateProvider);
  }

  void _showMessage(String message) =>
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
}

class _AddHolidayDialog extends ConsumerStatefulWidget {
  const _AddHolidayDialog({
    required this.initialDate,
    required this.selectedYear,
    required this.branches,
  });
  final DateTime initialDate;
  final int selectedYear;
  final List<Branch> branches;

  @override
  ConsumerState<_AddHolidayDialog> createState() => _AddHolidayDialogState();
}

class _AddHolidayDialogState extends ConsumerState<_AddHolidayDialog> {
  late final TextEditingController _nameController;
  late String _date;
  String _scope = 'all';
  String? _state;
  final Set<String> _branchIds = {};
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController();
    _date = _dateString(widget.initialDate);
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Add holiday'),
    content: SizedBox(
      width: 420,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            OutlinedButton.icon(
              key: const ValueKey('holiday-date-picker'),
              onPressed: _saving ? null : _chooseDate,
              icon: const Icon(Icons.calendar_month),
              label: Text(readableHolidayDate(_date)),
            ),
            TextField(
              key: const ValueKey('holiday-name'),
              controller: _nameController,
              maxLength: 100,
              enabled: !_saving,
              decoration: const InputDecoration(labelText: 'Name'),
            ),
            DropdownButtonFormField<String>(
              initialValue: _scope,
              decoration: const InputDecoration(labelText: 'Applies to'),
              items: const [
                DropdownMenuItem(value: 'all', child: Text('All branches')),
                DropdownMenuItem(
                  value: 'branches',
                  child: Text('Chosen branches'),
                ),
                DropdownMenuItem(
                  value: 'state',
                  child: Text('Every branch in a state'),
                ),
              ],
              onChanged: _saving
                  ? null
                  : (value) => setState(() {
                      _scope = value ?? 'all';
                      _branchIds.clear();
                    }),
            ),
            if (_scope == 'state')
              DropdownButtonFormField<String>(
                key: const ValueKey('holiday-state'),
                initialValue: _state,
                decoration: const InputDecoration(labelText: 'State'),
                items: groupBranchesByState(widget.branches).keys
                    .map(
                      (state) =>
                          DropdownMenuItem(value: state, child: Text(state)),
                    )
                    .toList(),
                onChanged: (value) => setState(() => _state = value),
              ),
            if (_scope == 'branches')
              for (final entry in groupBranchesByState(
                widget.branches,
              ).entries) ...[
                Align(
                  alignment: Alignment.centerLeft,
                  child: Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      entry.key,
                      style: Theme.of(context).textTheme.labelLarge,
                    ),
                  ),
                ),
                for (final id in entry.value)
                  CheckboxListTile(
                    dense: true,
                    title: Text(
                      widget.branches
                          .firstWhere((branch) => branch.id == id)
                          .name,
                    ),
                    value: _branchIds.contains(id),
                    onChanged: _saving
                        ? null
                        : (selected) => setState(() {
                            if (selected == true) {
                              _branchIds.add(id);
                            } else {
                              _branchIds.remove(id);
                            }
                          }),
                  ),
              ],
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: _saving ? null : () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: _saving ? null : _save,
        child: _saving
            ? const SizedBox.square(
                dimension: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Text('Save'),
      ),
    ],
  );

  Future<void> _chooseDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _dateTime(_date),
      firstDate: DateTime.utc(widget.selectedYear, 1, 1),
      lastDate: DateTime.utc(widget.selectedYear, 12, 31),
    );
    if (picked != null && mounted) setState(() => _date = _dateString(picked));
  }

  Future<void> _save() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      _showMessage('Enter a holiday name.');
      return;
    }
    final ids = _scope == 'state'
        ? groupBranchesByState(widget.branches)[_state] ?? const <String>[]
        : _scope == 'branches'
        ? (_branchIds.toList()..sort())
        : const <String>[];
    if ((_scope == 'state' && _state == null) ||
        (_scope == 'branches' && ids.isEmpty)) {
      _showMessage(
        _scope == 'state' ? 'Choose a state.' : 'Choose at least one branch.',
      );
      return;
    }
    setState(() => _saving = true);
    try {
      final holiday = await ref
          .read(attendanceViewsRepositoryProvider)
          .createHoliday(
            date: _date,
            name: name,
            scope: _scope == 'all' ? 'all' : 'branches',
            branchIds: ids,
          );
      if (mounted) Navigator.pop(context, holiday);
    } on AppException catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      _showMessage(error.message);
    }
  }

  void _showMessage(String message) =>
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
}

class _HolidayError extends StatelessWidget {
  const _HolidayError({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 36),
    child: Column(
      children: [
        Text(message, textAlign: TextAlign.center),
        const SizedBox(height: 12),
        OutlinedButton(onPressed: onRetry, child: const Text('Retry')),
      ],
    ),
  );
}

DateTime _dateTime(String date) => DateTime.parse('${date}T00:00:00Z');

String _dateString(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-'
    '${date.month.toString().padLeft(2, '0')}-'
    '${date.day.toString().padLeft(2, '0')}';

String _formatCreatedAt(String value) {
  final parsed = DateTime.tryParse(value)?.toUtc();
  if (parsed == null) return value;
  return '${readableHolidayDate(_dateString(parsed.add(const Duration(hours: 5, minutes: 30))))} '
      '${formatIstTime(value)} IST';
}

String _errorMessage(Object error) => switch (error) {
  AppException(:final message) => message,
  _ => 'Could not load holidays. Please try again.',
};
