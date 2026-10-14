import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/api/app_exception.dart';
import '../data/leave_providers.dart';
import '../domain/leave_type.dart';

class AdminLeaveTypesScreen extends ConsumerStatefulWidget {
  const AdminLeaveTypesScreen({super.key});
  @override
  ConsumerState<AdminLeaveTypesScreen> createState() =>
      _AdminLeaveTypesScreenState();
}

class _AdminLeaveTypesScreenState extends ConsumerState<AdminLeaveTypesScreen> {
  String _status = 'all';

  Future<void> _refresh() async {
    ref.invalidate(leaveTypesProvider(_status));
    await ref.read(leaveTypesProvider(_status).future);
  }

  Future<void> _setStatus(LeaveType type, String action) async {
    final activating = action == 'reactivate';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          activating ? 'Reactivate leave type?' : 'Deactivate leave type?',
        ),
        content: Text(
          '${activating ? 'Reactivate' : 'Deactivate'} ${type.name}?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(activating ? 'Reactivate' : 'Deactivate'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      final repository = ref.read(leaveRepositoryProvider);
      if (activating) {
        await repository.reactivateLeaveType(type.id);
      } else {
        await repository.deactivateLeaveType(type.id);
      }
      _invalidateTypes();
    } on AppException catch (error) {
      if (!mounted) return;
      final message = switch (error.code) {
        'LEAVE_TYPE_IN_USE' => _inUseMessage(error),
        _ => error.message,
      };
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
    }
  }

  Future<void> _selectAction(LeaveType type, String action) async {
    if (action == 'edit') {
      final saved = await context.push<bool>(
        '/admin/settings/leave-types/${Uri.encodeComponent(type.id)}',
      );
      if (saved == true) _invalidateTypes();
    } else {
      await _setStatus(type, action);
    }
  }

  void _invalidateTypes() {
    ref.invalidate(leaveTypesProvider);
    ref.invalidate(leaveBalanceProvider);
  }

  @override
  Widget build(BuildContext context) {
    final types = ref.watch(leaveTypesProvider(_status));
    return Scaffold(
      appBar: AppBar(title: const Text('Leave types')),
      floatingActionButton: FloatingActionButton.extended(
        key: const ValueKey('add-leave-type'),
        onPressed: () async {
          final saved = await context.push<bool>(
            '/admin/settings/leave-types/new',
          );
          if (saved == true) _invalidateTypes();
        },
        icon: const Icon(Icons.add),
        label: const Text('Add leave type'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'all', label: Text('All')),
                ButtonSegment(value: 'active', label: Text('Active')),
                ButtonSegment(value: 'inactive', label: Text('Inactive')),
              ],
              selected: {_status},
              onSelectionChanged: (value) =>
                  setState(() => _status = value.single),
            ),
          ),
          Expanded(
            child: types.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, _) => _ListError(
                error: error,
                retry: () => ref.invalidate(leaveTypesProvider(_status)),
              ),
              data: (items) => RefreshIndicator(
                onRefresh: _refresh,
                child: items.isEmpty
                    ? ListView(
                        children: const [
                          SizedBox(height: 150),
                          Center(child: Text('No leave types found.')),
                        ],
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(12, 0, 12, 88),
                        itemCount: items.length,
                        itemBuilder: (context, index) {
                          final type = items[index];
                          return Card(
                            child: ListTile(
                              key: ValueKey('leave-type-${type.id}'),
                              onTap: () async {
                                final saved = await context.push<bool>(
                                  '/admin/settings/leave-types/${Uri.encodeComponent(type.id)}',
                                );
                                if (saved == true) _invalidateTypes();
                              },
                              title: Text('${type.name} (${type.code})'),
                              subtitle: Wrap(
                                spacing: 4,
                                children: [
                                  Chip(label: Text(paidLabel(type.paid))),
                                  Chip(
                                    label: Text(
                                      type.annualQuotaDays == null
                                          ? 'No limit'
                                          : pluralDays(type.annualQuotaDays!),
                                    ),
                                  ),
                                  if (type.allowHalfDay)
                                    const Chip(label: Text('Half days')),
                                  if (type.status == 'inactive')
                                    const Chip(label: Text('Inactive')),
                                  if (type.system)
                                    const Chip(label: Text('System')),
                                ],
                              ),
                              trailing: PopupMenuButton<String>(
                                onSelected: (action) =>
                                    _selectAction(type, action),
                                itemBuilder: (context) => [
                                  const PopupMenuItem(
                                    value: 'edit',
                                    child: Text('Edit'),
                                  ),
                                  if (type.status == 'active' &&
                                      type.id != 'unpaid')
                                    const PopupMenuItem(
                                      value: 'deactivate',
                                      child: Text('Deactivate'),
                                    ),
                                  if (type.status == 'inactive' &&
                                      type.id != 'legacy-paid')
                                    const PopupMenuItem(
                                      value: 'reactivate',
                                      child: Text('Reactivate'),
                                    ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class AdminLeaveTypeFormScreen extends ConsumerStatefulWidget {
  const AdminLeaveTypeFormScreen({this.type, super.key});
  final LeaveType? type;
  @override
  ConsumerState<AdminLeaveTypeFormScreen> createState() =>
      _AdminLeaveTypeFormScreenState();
}

class _AdminLeaveTypeFormScreenState
    extends ConsumerState<AdminLeaveTypeFormScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _code;
  late final TextEditingController _quota;
  late final TextEditingController _sort;
  late bool _paid;
  late bool _allowHalf;
  late bool _noLimit;
  bool _saving = false;
  bool get _systemLocked => widget.type?.system == true;

  @override
  void initState() {
    super.initState();
    final type = widget.type;
    _name = TextEditingController(text: type?.name ?? '');
    _code = TextEditingController(text: type?.code ?? '');
    _quota = TextEditingController(
      text: type?.annualQuotaDays == null
          ? ''
          : formatDays(type!.annualQuotaDays!),
    );
    _sort = TextEditingController(
      text: type?.sortOrder == 0 ? '' : type?.sortOrder.toString() ?? '',
    );
    _paid = type?.paid ?? true;
    _allowHalf = type?.allowHalfDay ?? false;
    _noLimit = type == null ? false : type.annualQuotaDays == null;
  }

  @override
  void dispose() {
    _name.dispose();
    _code.dispose();
    _quota.dispose();
    _sort.dispose();
    super.dispose();
  }

  bool get _legacy => widget.type?.id == 'legacy-paid';

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final original = widget.type;
    final quota = _noLimit ? null : double.parse(_quota.text);
    final values = <String, Object?>{
      'name': _name.text.trim(),
      'code': _code.text.trim().toUpperCase(),
      'paid': _paid,
      'annualQuotaDays': quota,
      'allowHalfDay': _allowHalf,
      if (_sort.text.trim().isNotEmpty)
        'sortOrder': int.parse(_sort.text.trim()),
    };
    final changes = <String, Object?>{};
    if (original != null) {
      if (values['name'] != original.name) changes['name'] = values['name'];
      if (values['code'] != original.code) changes['code'] = values['code'];
      if (values['paid'] != original.paid && !_systemLocked) {
        changes['paid'] = values['paid'];
      }
      if (values['annualQuotaDays'] != original.annualQuotaDays &&
          !_systemLocked) {
        changes['annualQuotaDays'] = values['annualQuotaDays'];
      }
      if (values['allowHalfDay'] != original.allowHalfDay) {
        changes['allowHalfDay'] = values['allowHalfDay'];
      }
      if (_sort.text.trim().isNotEmpty &&
          values['sortOrder'] != original.sortOrder) {
        changes['sortOrder'] = values['sortOrder'];
      }
      if (changes.isEmpty) {
        context.pop(false);
        return;
      }
    }
    setState(() => _saving = true);
    try {
      if (original == null) {
        await ref.read(leaveRepositoryProvider).createLeaveType(values);
      } else {
        await ref
            .read(leaveRepositoryProvider)
            .updateLeaveType(original.id, changes);
      }
      ref.invalidate(leaveTypesProvider);
      ref.invalidate(leaveBalanceProvider);
      if (mounted) context.pop(true);
    } on AppException catch (error) {
      if (!mounted) return;
      final message = switch (error.code) {
        'LEAVE_TYPE_NAME_EXISTS' =>
          'A leave type with this name already exists.',
        'LEAVE_TYPE_CODE_EXISTS' => 'This code is already used.',
        _ => error.message,
      };
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(widget.type == null ? 'Add leave type' : 'Edit leave type'),
    ),
    body: Form(
      key: _formKey,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextFormField(
            key: const ValueKey('leave-type-name'),
            controller: _name,
            maxLength: 50,
            decoration: const InputDecoration(labelText: 'Name'),
            validator: (v) => (v ?? '').trim().isEmpty ? 'Enter a name.' : null,
          ),
          TextFormField(
            key: const ValueKey('leave-type-code'),
            controller: _code,
            maxLength: 6,
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp('[a-zA-Z0-9]')),
              UpperCaseTextFormatter(),
            ],
            decoration: const InputDecoration(labelText: 'Code'),
            validator: (v) =>
                RegExp(r'^[A-Z0-9]{1,6}$').hasMatch((v ?? '').trim())
                ? null
                : 'Use 1 to 6 letters or digits.',
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Paid leave'),
            value: _paid,
            onChanged: _saving || _systemLocked
                ? null
                : (v) => setState(() => _paid = v),
          ),
          const Text('Changing paid or unpaid only affects future approvals.'),
          if (_systemLocked)
            const Text(
              "This is a system type. Its paid status and quota can't be changed.",
            ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('No limit'),
            value: _noLimit,
            onChanged: _saving || _systemLocked
                ? null
                : (v) => setState(() => _noLimit = v),
          ),
          if (!_noLimit)
            TextFormField(
              key: const ValueKey('leave-type-quota'),
              controller: _quota,
              enabled: !_saving && !_systemLocked,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,1}')),
              ],
              decoration: const InputDecoration(
                labelText: 'Annual quota (days)',
              ),
              validator: (v) {
                if (_noLimit) return null;
                final n = double.tryParse((v ?? '').trim());
                if (n == null ||
                    n < 0.5 ||
                    n > 366 ||
                    (n * 2).round() != n * 2) {
                  return 'Enter 0.5 to 366 in 0.5 day steps.';
                }
                return null;
              },
            ),
          const Text(
            "Changing the quota changes everyone's remaining balance immediately.",
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Allow half days'),
            value: _allowHalf,
            onChanged: _saving ? null : (v) => setState(() => _allowHalf = v),
          ),
          TextFormField(
            key: const ValueKey('leave-type-sort-order'),
            controller: _sort,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: const InputDecoration(
              labelText: 'Sort order (optional)',
            ),
            validator: (v) {
              if ((v ?? '').trim().isEmpty) return null;
              final n = int.tryParse(v!.trim());
              return n != null && n <= 1000
                  ? null
                  : 'Enter an integer from 0 to 1000.';
            },
          ),
          if (_legacy)
            const Text(
              "Only used to display old requests. It can't be activated.",
            ),
          const SizedBox(height: 16),
          FilledButton(
            key: const ValueKey('save-leave-type'),
            onPressed: _saving ? null : _save,
            child: _saving
                ? const CircularProgressIndicator()
                : const Text('Save leave type'),
          ),
        ],
      ),
    ),
  );
}

class AdminLeaveTypeEditRoute extends ConsumerWidget {
  const AdminLeaveTypeEditRoute({required this.typeId, super.key});
  final String typeId;
  @override
  Widget build(BuildContext context, WidgetRef ref) => ref
      .watch(leaveTypesProvider('all'))
      .when(
        loading: () =>
            const Scaffold(body: Center(child: CircularProgressIndicator())),
        error: (error, _) => Scaffold(
          appBar: AppBar(),
          body: Center(
            child: Text(
              error is AppException
                  ? error.message
                  : 'Could not load leave type.',
            ),
          ),
        ),
        data: (types) {
          final type = types.where((item) => item.id == typeId).firstOrNull;
          return type == null
              ? const Scaffold(
                  body: Center(child: Text('Leave type not found.')),
                )
              : AdminLeaveTypeFormScreen(type: type);
        },
      );
}

class UpperCaseTextFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) => newValue.copyWith(
    text: newValue.text.toUpperCase(),
    selection: newValue.selection,
  );
}

String _inUseMessage(AppException error) {
  final count = error.details['pendingCount'];
  return count is num
      ? '${count.toInt()} pending requests use this type. Decide or cancel them first.'
      : 'Pending requests use this type. Decide or cancel them first.';
}

class _ListError extends StatelessWidget {
  const _ListError({required this.error, required this.retry});
  final Object error;
  final VoidCallback retry;
  @override
  Widget build(BuildContext context) => ListView(
    children: [
      const SizedBox(height: 100),
      Center(
        child: Text(
          error is AppException
              ? (error as AppException).message
              : 'Could not load leave types.',
        ),
      ),
      Center(
        child: TextButton(onPressed: retry, child: const Text('Retry')),
      ),
    ],
  );
}
