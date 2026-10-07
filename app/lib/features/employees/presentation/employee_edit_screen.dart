import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/api/app_exception.dart';
import '../../branches/domain/branch_assignment.dart';
import '../../branches/presentation/branch_assignment_fields.dart';
import '../data/employees_providers.dart';
import '../domain/employee.dart';
import '../domain/employee_dates.dart';

class EmployeeEditScreen extends ConsumerWidget {
  const EmployeeEditScreen({required this.id, super.key});

  final String id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final employeeState = ref.watch(employeeProvider(id));
    return Scaffold(
      appBar: AppBar(title: const Text('Edit employee')),
      body: employeeState.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                error is AppException
                    ? error.message
                    : 'Could not load employee.',
              ),
              TextButton(
                onPressed: () => ref.invalidate(employeeProvider(id)),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
        data: (employee) => _EditForm(employee: employee),
      ),
    );
  }
}

class _EditForm extends ConsumerStatefulWidget {
  const _EditForm({required this.employee});

  final Employee employee;

  @override
  ConsumerState<_EditForm> createState() => _EditFormState();
}

class _EditFormState extends ConsumerState<_EditForm> {
  final _formKey = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.employee.name);
  late final _phone = TextEditingController(text: widget.employee.phone ?? '');
  late final _designation = TextEditingController(
    text: widget.employee.designation ?? '',
  );
  late String _doj = widget.employee.doj;
  late BranchAssignment _assignment = BranchAssignment(
    primaryBranchId: widget.employee.primaryBranchId,
    allowedBranchIds: widget.employee.allowedBranchIds.toSet(),
  );
  bool _assignmentChanged = false;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _designation.dispose();
    super.dispose();
  }

  Future<void> _pickDoj() async {
    final selected = await showDatePicker(
      context: context,
      initialDate: parseDate(_doj),
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 365 * 5)),
    );
    if (selected != null) setState(() => _doj = formatDate(selected));
  }

  Future<void> _save() async {
    if (_saving || !_formKey.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref.read(employeeRepositoryProvider).updateEmployee(
        widget.employee.uid,
        {
          'name': _name.text.trim(),
          'phone': _phone.text.trim(),
          'designation': _designation.text.trim(),
          'doj': _doj,
          if (_assignmentChanged) ...{
            'primaryBranchId': _assignment.primaryBranchId,
            'allowedBranchIds': _assignment.allowedBranchIds.toList(),
          },
        },
      );
      ref.invalidate(employeeProvider(widget.employee.uid));
      ref.invalidate(employeesProvider('active'));
      ref.invalidate(employeesProvider('inactive'));
      ref.invalidate(employeesProvider('all'));
      if (mounted) context.pop(true);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error is AppException
            ? error.message
            : 'Could not update employee. Please try again.';
      });
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => Form(
    key: _formKey,
    child: SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
        if (_error != null)
          Text(
            _error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        TextFormField(
          initialValue: widget.employee.email,
          readOnly: true,
          decoration: const InputDecoration(
            labelText: 'Email',
            helperText: 'Email cannot be changed.',
          ),
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: _name,
          decoration: const InputDecoration(labelText: 'Name'),
          validator: (value) => value == null || value.trim().isEmpty
              ? 'Name is required.'
              : null,
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: _phone,
          keyboardType: TextInputType.phone,
          decoration: const InputDecoration(labelText: 'Phone (optional)'),
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: _designation,
          decoration: const InputDecoration(
            labelText: 'Designation (optional)',
          ),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: _pickDoj,
          icon: const Icon(Icons.calendar_month),
          label: Text('Date of joining: $_doj'),
        ),
        const SizedBox(height: 16),
        BranchAssignmentFields(
          assignment: _assignment,
          onChanged: (value) => setState(() {
            _assignment = value;
            _assignmentChanged = true;
          }),
        ),
        const SizedBox(height: 24),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: _saving
              ? const CircularProgressIndicator()
              : const Text('Save changes'),
        ),
          ],
        ),
      ),
    ),
  );
}
