import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/app_exception.dart';
import '../data/attendance_views_providers.dart';
import '../domain/attendance_views.dart';

class AdminAttendanceSettingsScreen extends ConsumerWidget {
  const AdminAttendanceSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(attendanceSettingsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Attendance settings')),
      body: settings.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => _SettingsError(
          message: _errorMessage(error),
          onRetry: () => ref.invalidate(attendanceSettingsProvider),
        ),
        data: (value) => _SettingsForm(settings: value),
      ),
    );
  }
}

class _SettingsForm extends ConsumerStatefulWidget {
  const _SettingsForm({required this.settings});

  final AttendanceSettings settings;

  @override
  ConsumerState<_SettingsForm> createState() => _SettingsFormState();
}

class _SettingsFormState extends ConsumerState<_SettingsForm> {
  late final TextEditingController _companyName;
  late final Set<int> _weeklyOffDays;
  late String _perDayBasis;
  late int _maxAccuracy;
  late bool _rejectMockLocation;
  late bool _enforceCheckoutLocation;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _companyName = TextEditingController(text: widget.settings.companyName);
    _weeklyOffDays = widget.settings.weeklyOffDays.toSet();
    _perDayBasis = widget.settings.perDayBasis;
    _maxAccuracy = widget.settings.maxAccuracyMeters;
    _rejectMockLocation = widget.settings.rejectMockLocation;
    _enforceCheckoutLocation = widget.settings.enforceCheckoutLocation;
  }

  @override
  void dispose() {
    _companyName.dispose();
    super.dispose();
  }

  Map<String, Object?> get _changes {
    final original = widget.settings;
    final changes = <String, Object?>{};
    final companyName = _companyName.text.trim();
    if (companyName != original.companyName) {
      changes['companyName'] = companyName;
    }
    final weeklyOffDays = _weeklyOffDays.toList()..sort();
    final originalDays = original.weeklyOffDays.toList()..sort();
    if (!_sameList(weeklyOffDays, originalDays)) {
      changes['weeklyOffDays'] = weeklyOffDays;
    }
    if (_perDayBasis != original.perDayBasis) {
      changes['perDayBasis'] = _perDayBasis;
    }
    if (_maxAccuracy != original.maxAccuracyMeters) {
      changes['maxAccuracyMeters'] = _maxAccuracy;
    }
    if (_rejectMockLocation != original.rejectMockLocation) {
      changes['rejectMockLocation'] = _rejectMockLocation;
    }
    if (_enforceCheckoutLocation != original.enforceCheckoutLocation) {
      changes['enforceCheckoutLocation'] = _enforceCheckoutLocation;
    }
    return changes;
  }

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(16),
    children: [
      TextField(
        key: const ValueKey('settings-company-name'),
        controller: _companyName,
        maxLength: 120,
        enabled: !_saving,
        decoration: const InputDecoration(labelText: 'Company name'),
        onChanged: (_) => setState(() {}),
      ),
      const SizedBox(height: 8),
      Text('Weekly off days', style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 4),
      Wrap(
        spacing: 6,
        children: [
          for (var weekday = 0; weekday < 7; weekday++)
            FilterChip(
              key: ValueKey('weekly-off-$weekday'),
              label: Text(_weekdayName(weekday)),
              selected: _weeklyOffDays.contains(weekday),
              onSelected: _saving
                  ? null
                  : (selected) {
                      setState(() {
                        if (selected) {
                          _weeklyOffDays.add(weekday);
                        } else {
                          _weeklyOffDays.remove(weekday);
                        }
                      });
                    },
            ),
        ],
      ),
      const SizedBox(height: 4),
      const Text('Changing this also changes past months that are not locked.'),
      const SizedBox(height: 20),
      Text('Per-day basis', style: Theme.of(context).textTheme.titleMedium),
      SegmentedButton<String>(
        segments: const [
          ButtonSegment(value: 'calendar', label: Text('Calendar days')),
          ButtonSegment(value: 'working', label: Text('Working days')),
        ],
        selected: {_perDayBasis},
        onSelectionChanged: _saving
            ? null
            : (selection) => setState(() => _perDayBasis = selection.single),
      ),
      const SizedBox(height: 20),
      Text('Maximum GPS accuracy: $_maxAccuracy m'),
      Slider(
        key: const ValueKey('settings-max-accuracy'),
        min: 10,
        max: 500,
        divisions: 49,
        value: _maxAccuracy.toDouble(),
        label: '$_maxAccuracy m',
        onChanged: _saving
            ? null
            : (value) => setState(() => _maxAccuracy = value.round()),
      ),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('Reject mock locations'),
        value: _rejectMockLocation,
        onChanged: _saving
            ? null
            : (value) => setState(() => _rejectMockLocation = value),
      ),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('Enforce location on check-out'),
        value: _enforceCheckoutLocation,
        onChanged: _saving
            ? null
            : (value) => setState(() => _enforceCheckoutLocation = value),
      ),
      const SizedBox(height: 16),
      FilledButton(
        key: const ValueKey('save-attendance-settings'),
        onPressed: _saving || _changes.isEmpty ? null : _save,
        child: _saving
            ? const SizedBox.square(
                dimension: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Text('Save settings'),
      ),
    ],
  );

  Future<void> _save() async {
    final changes = _changes;
    if (changes.isEmpty) return;
    setState(() => _saving = true);
    try {
      await ref
          .read(attendanceViewsRepositoryProvider)
          .updateSettings(changes);
      if (!mounted) return;
      ref.invalidate(attendanceSettingsProvider);
      ref.invalidate(myAttendanceCalendarProvider);
      ref.invalidate(employeeAttendanceCalendarProvider);
      ref.invalidate(attendanceSummaryProvider);
      ref.invalidate(attendanceByDateProvider);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Attendance settings saved.')),
      );
    } on AppException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message)));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}

class _SettingsError extends StatelessWidget {
  const _SettingsError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(message, textAlign: TextAlign.center),
        const SizedBox(height: 12),
        OutlinedButton(onPressed: onRetry, child: const Text('Retry')),
      ],
    ),
  );
}

String _weekdayName(int weekday) => const [
  'Sun',
  'Mon',
  'Tue',
  'Wed',
  'Thu',
  'Fri',
  'Sat',
][weekday];

bool _sameList(List<int> first, List<int> second) {
  if (first.length != second.length) return false;
  for (var index = 0; index < first.length; index++) {
    if (first[index] != second[index]) return false;
  }
  return true;
}

String _errorMessage(Object error) => switch (error) {
  AppException(:final message) => message,
  _ => 'Could not load attendance settings. Please try again.',
};
