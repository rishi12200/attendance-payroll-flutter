import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/api/app_exception.dart';
import '../../../core/auth/auth_providers.dart';
import '../data/employees_providers.dart';
import '../domain/employee.dart';
import '../domain/employee_dates.dart';
import '../domain/money.dart';
import '../domain/salary_revision.dart';

class EmployeeDetailScreen extends ConsumerWidget {
  const EmployeeDetailScreen({required this.id, super.key});

  final String id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final employeeState = ref.watch(employeeProvider(id));
    final profile = ref.watch(currentProfileProvider).asData?.value;
    return Scaffold(
      appBar: AppBar(title: const Text('Employee details')),
      body: employeeState.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => _ErrorPanel(
          message: _messageFor(error),
          onRetry: () => ref.invalidate(employeeProvider(id)),
        ),
        data: (employee) => _EmployeeDetails(
          employee: employee,
          isSelf: profile?.uid == employee.uid,
        ),
      ),
    );
  }

  String _messageFor(Object error) {
    if (error is AppException) return error.message;
    return 'Could not load employee. Please try again.';
  }
}

class _EmployeeDetails extends ConsumerWidget {
  const _EmployeeDetails({required this.employee, required this.isSelf});

  final Employee employee;
  final bool isSelf;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final salaryState = ref.watch(salaryHistoryProvider(employee.uid));
    final canDeactivate =
        employee.role == 'employee' &&
        employee.status == EmployeeStatus.active &&
        !isSelf;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  employee.name,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                Text(employee.empCode),
                const SizedBox(height: 12),
                _FieldLine(label: 'Email', value: employee.email),
                _FieldLine(label: 'Phone', value: employee.phone ?? '—'),
                _FieldLine(
                  label: 'Designation',
                  value: employee.designation ?? '—',
                ),
                _FieldLine(label: 'Role', value: employee.role),
                _FieldLine(
                  label: 'Status',
                  value: employee.status == EmployeeStatus.active
                      ? 'Active'
                      : 'Inactive',
                ),
                _FieldLine(label: 'Date of joining', value: employee.doj),
                _FieldLine(
                  label: 'Date of leaving',
                  value: employee.dol ?? '—',
                ),
                _FieldLine(
                  label: 'Current monthly salary',
                  value: employee.currentMonthlyCtcPaise == null
                      ? 'Not set'
                      : paiseToDisplay(employee.currentMonthlyCtcPaise!),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  children: [
                    OutlinedButton.icon(
                      onPressed: () async {
                        final changed = await context.push<bool>(
                          '/admin/employees/${employee.uid}/edit',
                        );
                        if (changed == true) {
                          ref.invalidate(employeeProvider(employee.uid));
                          _invalidateLists(ref);
                        }
                      },
                      icon: const Icon(Icons.edit),
                      label: const Text('Edit'),
                    ),
                    if (canDeactivate)
                      FilledButton.tonalIcon(
                        onPressed: () => _confirmDeactivate(context, ref),
                        icon: const Icon(Icons.person_off_outlined),
                        label: const Text('Deactivate'),
                      ),
                    if (employee.role == 'employee' &&
                        employee.status == EmployeeStatus.inactive)
                      FilledButton.tonalIcon(
                        onPressed: () => _reactivate(context, ref),
                        icon: const Icon(Icons.person_add_alt),
                        label: const Text('Reactivate'),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Salary history',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            TextButton.icon(
              onPressed: () => _addSalaryRevision(context, ref, employee),
              icon: const Icon(Icons.add),
              label: const Text('Add revision'),
            ),
          ],
        ),
        salaryState.when(
          loading: () => const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (error, _) => _ErrorPanel(
            message: _messageFor(error),
            onRetry: () => ref.invalidate(salaryHistoryProvider(employee.uid)),
          ),
          data: (revisions) => revisions.isEmpty
              ? const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('No salary revisions found.'),
                )
              : Column(
                  children: revisions
                      .map((revision) => _SalaryCard(revision: revision))
                      .toList(growable: false),
                ),
        ),
      ],
    );
  }

  Future<void> _confirmDeactivate(BuildContext context, WidgetRef ref) async {
    final dol = await showDialog<String>(
      context: context,
      builder: (context) => _DeactivateDialog(doj: employee.doj),
    );
    if (dol == null || !context.mounted) return;
    try {
      await ref
          .read(employeeRepositoryProvider)
          .deactivate(employee.uid, dol: dol);
      _invalidateLists(ref);
      ref.invalidate(employeeProvider(employee.uid));
    } catch (error) {
      if (!context.mounted) return;
      _showMessage(context, _messageFor(error));
    }
  }

  Future<void> _reactivate(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Reactivate employee?'),
        content: const Text('This will restore the employee account.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Reactivate'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    try {
      await ref.read(employeeRepositoryProvider).reactivate(employee.uid);
      _invalidateLists(ref);
      ref.invalidate(employeeProvider(employee.uid));
    } catch (error) {
      if (!context.mounted) return;
      _showMessage(context, _messageFor(error));
    }
  }

  Future<void> _addSalaryRevision(
    BuildContext context,
    WidgetRef ref,
    Employee employee,
  ) async {
    final revision = await showDialog<_SalaryRevisionInput>(
      context: context,
      builder: (context) => _SalaryRevisionDialog(doj: employee.doj),
    );
    if (revision == null || !context.mounted) return;
    try {
      await ref
          .read(employeeRepositoryProvider)
          .addSalaryRevision(
            employee.uid,
            revision.effectiveFrom,
            revision.monthlyCtcPaise,
          );
      ref.invalidate(salaryHistoryProvider(employee.uid));
      ref.invalidate(employeeProvider(employee.uid));
      _invalidateLists(ref);
    } catch (error) {
      if (!context.mounted) return;
      _showMessage(context, _messageFor(error));
    }
  }

  String _messageFor(Object error) {
    if (error is AppException) return error.message;
    return 'Could not save the employee. Please try again.';
  }

  void _showMessage(BuildContext context, String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }
}

class _FieldLine extends StatelessWidget {
  const _FieldLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 150,
          child: Text(label, style: Theme.of(context).textTheme.labelLarge),
        ),
        Expanded(child: Text(value)),
      ],
    ),
  );
}

class _SalaryCard extends StatelessWidget {
  const _SalaryCard({required this.revision});

  final SalaryRevision revision;

  @override
  Widget build(BuildContext context) => Card(
    child: ListTile(
      title: Text(paiseToDisplay(revision.monthlyCtcPaise)),
      subtitle: Text('Effective from ${revision.effectiveFrom}'),
    ),
  );
}

class _SalaryRevisionInput {
  const _SalaryRevisionInput({
    required this.effectiveFrom,
    required this.monthlyCtcPaise,
  });

  final String effectiveFrom;
  final int monthlyCtcPaise;
}

class _ErrorPanel extends StatelessWidget {
  const _ErrorPanel({required this.message, required this.onRetry});

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
          OutlinedButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    ),
  );
}

class _DeactivateDialog extends StatefulWidget {
  const _DeactivateDialog({required this.doj});

  final String doj;

  @override
  State<_DeactivateDialog> createState() => _DeactivateDialogState();
}

class _DeactivateDialogState extends State<_DeactivateDialog> {
  late String _dol = _defaultDol();

  String _defaultDol() {
    final today = parseDate(todayIST());
    final joining = parseDate(widget.doj);
    return formatDate(today.isBefore(joining) ? joining : today);
  }

  Future<void> _pickDate() async {
    final selected = await showDatePicker(
      context: context,
      initialDate: parseDate(_dol).isBefore(parseDate(widget.doj))
          ? parseDate(widget.doj)
          : parseDate(_dol),
      firstDate: parseDate(widget.doj),
      lastDate: DateTime.now().add(const Duration(days: 365 * 5)),
    );
    if (selected != null) setState(() => _dol = formatDate(selected));
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Deactivate employee?'),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('The employee will no longer be able to sign in.'),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: _pickDate,
          icon: const Icon(Icons.calendar_month),
          label: Text('Last working day: $_dol'),
        ),
      ],
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(context, _dol),
        child: const Text('Deactivate'),
      ),
    ],
  );
}

class _SalaryRevisionDialog extends StatefulWidget {
  const _SalaryRevisionDialog({required this.doj});

  final String doj;

  @override
  State<_SalaryRevisionDialog> createState() => _SalaryRevisionDialogState();
}

class _SalaryRevisionDialogState extends State<_SalaryRevisionDialog> {
  final _formKey = GlobalKey<FormState>();
  final _amount = TextEditingController();
  late String _effectiveFrom = _defaultEffectiveDate();

  String _defaultEffectiveDate() {
    final today = parseDate(todayIST());
    final joining = parseDate(widget.doj);
    return formatDate(today.isBefore(joining) ? joining : today);
  }

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final selected = await showDatePicker(
      context: context,
      initialDate: parseDate(_effectiveFrom),
      firstDate: parseDate(widget.doj),
      lastDate: DateTime.now().add(const Duration(days: 365 * 5)),
    );
    if (selected != null) setState(() => _effectiveFrom = formatDate(selected));
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Add salary revision'),
    content: Form(
      key: _formKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          OutlinedButton.icon(
            onPressed: _pickDate,
            icon: const Icon(Icons.calendar_month),
            label: Text('Effective from: $_effectiveFrom'),
          ),
          TextFormField(
            controller: _amount,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: 'Monthly salary (₹)'),
            validator: (value) => rupeesStringToPaise(value ?? '') == null
                ? 'Enter a positive amount with at most 2 decimals.'
                : null,
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () {
          if (!_formKey.currentState!.validate()) return;
          Navigator.pop(
            context,
            _SalaryRevisionInput(
              effectiveFrom: _effectiveFrom,
              monthlyCtcPaise: rupeesStringToPaise(_amount.text)!,
            ),
          );
        },
        child: const Text('Save'),
      ),
    ],
  );
}

void _invalidateLists(WidgetRef ref) {
  ref.invalidate(employeesProvider('active'));
  ref.invalidate(employeesProvider('inactive'));
  ref.invalidate(employeesProvider('all'));
}
