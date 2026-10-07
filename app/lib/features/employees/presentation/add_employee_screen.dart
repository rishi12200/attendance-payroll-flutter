import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/api/app_exception.dart';
import '../data/employees_providers.dart';
import '../domain/employee_dates.dart';
import '../domain/money.dart';

class AddEmployeeScreen extends ConsumerStatefulWidget {
  const AddEmployeeScreen({super.key});

  @override
  ConsumerState<AddEmployeeScreen> createState() => _AddEmployeeScreenState();
}

class _AddEmployeeScreenState extends ConsumerState<AddEmployeeScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _phone = TextEditingController();
  final _designation = TextEditingController();
  final _salary = TextEditingController();
  String _doj = todayIST();
  bool _obscurePassword = true;
  bool _submitting = false;
  String? _errorMessage;
  Map<String, String> _fieldErrors = {};

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.clear();
    _password.dispose();
    _phone.dispose();
    _designation.dispose();
    _salary.dispose();
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

  Future<void> _submit() async {
    if (_submitting || !_formKey.currentState!.validate()) return;
    final paise = rupeesStringToPaise(_salary.text)!;
    setState(() {
      _submitting = true;
      _errorMessage = null;
      _fieldErrors = {};
    });

    try {
      final employee = await ref
          .read(employeeRepositoryProvider)
          .createEmployee(
            name: _name.text.trim(),
            email: _email.text.trim().toLowerCase(),
            tempPassword: _password.text,
            phone: _phone.text.trim().isEmpty ? null : _phone.text.trim(),
            designation: _designation.text.trim().isEmpty
                ? null
                : _designation.text.trim(),
            doj: _doj,
            monthlyCtcPaise: paise,
          );
      _password.clear();
      ref.invalidate(employeesProvider('active'));
      ref.invalidate(employeesProvider('inactive'));
      ref.invalidate(employeesProvider('all'));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Share the temporary password securely with the employee.',
          ),
        ),
      );
      context.go('/admin/employees/${employee.uid}');
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _errorMessage = _messageFor(error);
        _fieldErrors = _serverFieldErrors(error);
      });
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  String _messageFor(Object error) {
    if (error is AppException && error.statusCode == 409) {
      return 'An employee with this email already exists.';
    }
    if (error is AppException) return error.message;
    return 'Could not create employee. Please try again.';
  }

  Map<String, String> _serverFieldErrors(Object error) {
    if (error is! AppException) return {};
    final issues = error.details['issues'];
    if (issues is! List) return {};
    final result = <String, String>{};
    for (final issue in issues) {
      if (issue is Map && issue['path'] is String && issue['message'] is String) {
        result[issue['path'] as String] = issue['message'] as String;
      }
    }
    return result;
  }

  String? _required(String? value, String label, {int minLength = 1}) {
    final text = value?.trim() ?? '';
    if (text.isEmpty) return '$label is required.';
    if (text.length < minLength) return '$label must be at least $minLength characters.';
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Add employee')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (_errorMessage != null) ...[
              _ErrorMessage(message: _errorMessage!),
              const SizedBox(height: 12),
            ],
            TextFormField(
              controller: _name,
              decoration: InputDecoration(
                labelText: 'Name',
                errorText: _fieldErrors['name'],
              ),
              validator: (value) => _required(value, 'Name'),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              decoration: InputDecoration(
                labelText: 'Email',
                errorText: _fieldErrors['email'],
              ),
              validator: (value) {
                final requiredError = _required(value, 'Email');
                if (requiredError != null) return requiredError;
                if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$')
                    .hasMatch(value!.trim())) {
                  return 'Enter a valid email address.';
                }
                return null;
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _password,
              obscureText: _obscurePassword,
              decoration: InputDecoration(
                labelText: 'Temporary password',
                helperText: 'At least 8 characters. Share it securely.',
                errorText: _fieldErrors['tempPassword'],
                suffixIcon: IconButton(
                  tooltip: _obscurePassword ? 'Show password' : 'Hide password',
                  onPressed: () =>
                      setState(() => _obscurePassword = !_obscurePassword),
                  icon: Icon(
                    _obscurePassword ? Icons.visibility : Icons.visibility_off,
                  ),
                ),
              ),
              validator: (value) =>
                  _required(value, 'Password', minLength: 8),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _phone,
              keyboardType: TextInputType.phone,
              decoration: InputDecoration(
                labelText: 'Phone (optional)',
                errorText: _fieldErrors['phone'],
              ),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _designation,
              decoration: InputDecoration(
                labelText: 'Designation (optional)',
                errorText: _fieldErrors['designation'],
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _pickDoj,
              icon: const Icon(Icons.calendar_month),
              label: Text('Date of joining: $_doj'),
            ),
            if (_fieldErrors['doj'] case final error?) ...[
              const SizedBox(height: 4),
              Text(error, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ],
            const SizedBox(height: 12),
            TextFormField(
              controller: _salary,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: 'Monthly salary (₹)',
                errorText: _fieldErrors['monthlyCtcPaise'],
              ),
              validator: (value) => rupeesStringToPaise(value ?? '') == null
                  ? 'Enter a positive amount with at most 2 decimals.'
                  : null,
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _submitting ? null : _submit,
              child: _submitting
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Create employee'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorMessage extends StatelessWidget {
  const _ErrorMessage({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) => Text(
    message,
    style: TextStyle(color: Theme.of(context).colorScheme.error),
  );
}
