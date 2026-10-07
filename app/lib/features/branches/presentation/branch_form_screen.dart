import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/api/app_exception.dart';
import '../data/branches_providers.dart';
import '../data/location_providers.dart';
import '../domain/branch.dart';
import '../domain/branch_form_validation.dart';
import '../domain/location_service.dart';

class BranchFormScreen extends ConsumerWidget {
  const BranchFormScreen({this.id, super.key});

  final String? id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (id == null) return const _BranchForm();
    final branch = ref.watch(branchProvider(id!));
    return Scaffold(
      appBar: AppBar(title: const Text('Edit branch')),
      body: branch.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_errorMessage(error)),
              TextButton(
                onPressed: () => ref.invalidate(branchProvider(id!)),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
        data: (value) => _BranchForm(branch: value),
      ),
    );
  }
}

class _BranchForm extends ConsumerStatefulWidget {
  const _BranchForm({this.branch});

  final Branch? branch;

  @override
  ConsumerState<_BranchForm> createState() => _BranchFormState();
}

class _BranchFormState extends ConsumerState<_BranchForm> {
  final _formKey = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.branch?.name ?? '');
  late final _address = TextEditingController(
    text: widget.branch?.address ?? '',
  );
  late final _state = TextEditingController(text: widget.branch?.state ?? '');
  late final _latitude = TextEditingController(
    text: widget.branch?.lat.toString() ?? '',
  );
  late final _longitude = TextEditingController(
    text: widget.branch?.lng.toString() ?? '',
  );
  late double _radius = (widget.branch?.radiusMeters ?? 100).toDouble();
  bool _saving = false;
  bool _gettingLocation = false;
  String? _error;
  String? _accuracy;

  @override
  void dispose() {
    _name.dispose();
    _address.dispose();
    _state.dispose();
    _latitude.dispose();
    _longitude.dispose();
    super.dispose();
  }

  Future<void> _useCurrentLocation() async {
    if (_gettingLocation) return;
    setState(() {
      _gettingLocation = true;
      _error = null;
    });
    final result = await ref.read(locationServiceProvider).getCurrentPosition();
    if (!mounted) return;
    switch (result) {
      case LocationSuccess():
        setState(() {
          _latitude.text = result.latitude.toStringAsFixed(6);
          _longitude.text = result.longitude.toStringAsFixed(6);
          _accuracy = '${result.accuracy.toStringAsFixed(0)} m';
        });
      case LocationFailure():
        setState(() => _error = _locationMessage(result.reason));
        if (result.reason == LocationFailureReason.permissionDeniedForever ||
            result.reason == LocationFailureReason.serviceDisabled) {
          _showSettingsAction(result.reason);
        }
    }
    setState(() => _gettingLocation = false);
  }

  void _showSettingsAction(LocationFailureReason reason) {
    final label = reason == LocationFailureReason.serviceDisabled
        ? 'Open location settings'
        : 'Open app settings';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(_locationMessage(reason)),
        action: SnackBarAction(
          label: label,
          onPressed: () {
            ref.read(locationServiceProvider).openSettings(reason);
          },
        ),
      ),
    );
  }

  String _locationMessage(LocationFailureReason reason) => switch (reason) {
    LocationFailureReason.serviceDisabled =>
      'Location services are off. Turn them on to use your current location.',
    LocationFailureReason.permissionDenied => 'Location permission was denied. Allow access to use your current location.',
    LocationFailureReason.permissionDeniedForever =>
      'Location permission is blocked. Open app settings to allow access.',
    LocationFailureReason.timeout =>
      'Could not get a location fix within 15 seconds. Try again.',
    LocationFailureReason.unknown =>
      'Could not get your location. Check the device settings and try again.',
  };

  Future<void> _save() async {
    if (_saving || !_formKey.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    final values = <String, Object?>{
      'name': _name.text.trim(),
      'address': _address.text.trim(),
      'state': _state.text.trim(),
      'lat': double.parse(_latitude.text.trim()),
      'lng': double.parse(_longitude.text.trim()),
      'radiusMeters': _radius.round(),
    };
    try {
      final repository = ref.read(branchRepositoryProvider);
      final saved = widget.branch == null
          ? await repository.createBranch(values)
          : await repository.updateBranch(
              widget.branch!.id,
              _changedFields(values, widget.branch!),
            );
      ref.invalidate(branchesProvider('active'));
      ref.invalidate(branchesProvider('inactive'));
      ref.invalidate(branchesProvider('all'));
      if (widget.branch != null) {
        ref.invalidate(branchProvider(saved.id));
      }
      if (mounted) context.pop(true);
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = _errorMessage(error));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Map<String, Object?> _changedFields(
    Map<String, Object?> values,
    Branch branch,
  ) {
    final changed = <String, Object?>{};
    if (values['name'] != branch.name) changed['name'] = values['name'];
    if (values['address'] != (branch.address ?? '')) {
      changed['address'] = values['address'];
    }
    if (values['state'] != branch.state) changed['state'] = values['state'];
    if (values['lat'] != branch.lat) changed['lat'] = values['lat'];
    if (values['lng'] != branch.lng) changed['lng'] = values['lng'];
    if (values['radiusMeters'] != branch.radiusMeters) {
      changed['radiusMeters'] = values['radiusMeters'];
    }
    return changed;
  }

  Future<void> _changeStatus() async {
    final branch = widget.branch!;
    final activate = branch.status == BranchStatus.inactive;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('${activate ? 'Reactivate' : 'Deactivate'} branch?'),
        content: Text(
          activate ? 'This branch will be available for assignment.' : 'Employees assigned to this branch cannot use it while inactive.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(activate ? 'Reactivate' : 'Deactivate'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      final repository = ref.read(branchRepositoryProvider);
      if (activate) {
        await repository.reactivate(branch.id);
      } else {
        await repository.deactivate(branch.id);
      }
      ref.invalidate(branchProvider(branch.id));
      ref.invalidate(branchesProvider('active'));
      ref.invalidate(branchesProvider('inactive'));
      ref.invalidate(branchesProvider('all'));
    } catch (error) {
      if (mounted) {
        final message = _errorMessage(error);
        setState(() => _error = message);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(message)));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final editing = widget.branch != null;
    return Scaffold(
      appBar: AppBar(title: Text(editing ? 'Edit branch' : 'Add branch')),
      body: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
            if (_error != null) ...[
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
              const SizedBox(height: 12),
            ],
            TextFormField(
              controller: _name,
              decoration: const InputDecoration(labelText: 'Name'),
              validator: (value) => value == null || value.trim().isEmpty
                  ? 'Name is required.'
                  : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _address,
              decoration: const InputDecoration(
                labelText: 'Address (optional)',
              ),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _state,
              decoration: const InputDecoration(labelText: 'State'),
              validator: (value) => value == null || value.trim().isEmpty
                  ? 'State is required.'
                  : null,
            ),
            const SizedBox(height: 12),
            FilledButton.tonalIcon(
              onPressed: _gettingLocation ? null : _useCurrentLocation,
              icon: const Icon(Icons.my_location),
              label: Text(
                _gettingLocation
                    ? 'Getting location...'
                    : 'Use my current location',
              ),
            ),
            if (_accuracy case final value?) Text('Reported accuracy: $value'),
            const SizedBox(height: 12),
            TextFormField(
              controller: _latitude,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
                signed: true,
              ),
              decoration: const InputDecoration(labelText: 'Latitude'),
              validator: validateLatitude,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _longitude,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
                signed: true,
              ),
              decoration: const InputDecoration(labelText: 'Longitude'),
              validator: validateLongitude,
            ),
            const SizedBox(height: 20),
            Text('Radius: ${_radius.round()} metres'),
            Slider(
              value: _radius,
              min: 20,
              max: 1000,
              divisions: 980,
              label: '${_radius.round()} m',
              onChanged: (value) =>
                  setState(() => _radius = value.roundToDouble()),
            ),
            if (validateRadius(_radius.round().toString()) case final error?)
              Text(error),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const CircularProgressIndicator()
                  : Text(editing ? 'Save changes' : 'Create branch'),
            ),
            if (editing) ...[
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: _changeStatus,
                child: Text(
                  widget.branch!.status == BranchStatus.active
                      ? 'Deactivate branch'
                      : 'Reactivate branch',
                ),
              ),
            ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

String _errorMessage(Object error) {
  if (error is AppException && error.code == 'BRANCH_NAME_EXISTS') {
    return 'A branch with this name already exists.';
  }
  if (error is AppException) return error.message;
  return 'Could not save branch. Please try again.';
}
