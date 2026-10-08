import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/auth_providers.dart';
import '../../../features/branches/data/location_providers.dart';
import '../../../features/branches/domain/location_service.dart';
import '../domain/attendance_controller.dart';
import '../domain/attendance_error_messages.dart';
import '../domain/attendance_helpers.dart';
import 'location_estimate.dart';

class EmployeeAttendanceScreen extends ConsumerStatefulWidget {
  const EmployeeAttendanceScreen({super.key});

  @override
  ConsumerState<EmployeeAttendanceScreen> createState() =>
      _EmployeeAttendanceScreenState();
}

class _EmployeeAttendanceScreenState
    extends ConsumerState<EmployeeAttendanceScreen>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      final uid = ref.read(signedInUidProvider);
      if (uid == null) return;
      ref.read(attendanceControllerProvider.notifier).refresh();
      ref.invalidate(locationEstimateProvider(uid));
    }
  }

  Future<void> _refresh(String uid) async {
    ref.invalidate(employeeBranchesProvider(uid));
    await Future.wait([
      ref.read(attendanceControllerProvider.notifier).refresh(),
      ref.refresh(locationEstimateProvider(uid).future).then<void>((_) {}),
    ]);
  }

  Future<void> _signOut() async {
    try {
      await ref.read(authControllerProvider).signOut();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not sign out. Please try again.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(currentProfileProvider).asData?.value;
    final uid = ref.watch(signedInUidProvider);
    final state = uid == null
        ? const AttendanceLoading()
        : ref.watch(attendanceControllerProvider);
    final estimate = uid == null
        ? const AsyncLoading<LocationEstimate>()
        : ref.watch(locationEstimateProvider(uid));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Employee home'),
        backgroundColor: Theme.of(context).colorScheme.tertiaryContainer,
        actions: [
          IconButton(
            tooltip: 'Log out',
            onPressed: _signOut,
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: uid == null ? () async {} : () => _refresh(uid),
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              profile?.name ?? 'Employee',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 4),
            if (state
                case AttendanceNotCheckedIn(:final today) ||
                    AttendanceCheckedIn(:final today) ||
                    AttendanceCompleted(:final today))
              Text(_formatDate(today)),
            const SizedBox(height: 16),
            _buildAttendanceContent(context, state, estimate, uid),
            const SizedBox(height: 16),
            _buildDistanceCard(context, estimate, uid),
            if (state.feedback != null) ...[
              const SizedBox(height: 16),
              _buildFeedback(context, state),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildAttendanceContent(
    BuildContext context,
    AttendanceHomeState state,
    AsyncValue<LocationEstimate> estimate,
    String? uid,
  ) {
    if (state is AttendanceLoading) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: CircularProgressIndicator(),
        ),
      );
    }
    if (state is AttendanceLoadError) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              const Text('Could not load your attendance.'),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: () =>
                    ref.read(attendanceControllerProvider.notifier).refresh(),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    final isNoBranch =
        uid != null &&
        ref
            .watch(employeeBranchesProvider(uid))
            .maybeWhen(
              data: (branches) => branches.isEmpty,
              orElse: () => false,
            );
    final card = switch (state) {
      AttendanceNotCheckedIn() => _statusCard(
        context,
        title: 'Not checked in',
        icon: Icons.login,
        children: const [],
      ),
      AttendanceCheckedIn(:final inTime, :final branchName) => _statusCard(
        context,
        title: 'Checked in at ${formatIstTime(inTime)}',
        icon: Icons.login,
        children: [Text(branchName)],
      ),
      AttendanceCompleted(
        :final inTime,
        :final outTime,
        :final workedMinutes,
      ) =>
        _statusCard(
          context,
          title: 'Done for today',
          icon: Icons.task_alt,
          children: [
            Text('In: ${formatIstTime(inTime)}'),
            Text('Out: ${formatIstTime(outTime)}'),
            Text('Worked: ${formatWorkedMinutes(workedMinutes)}'),
          ],
        ),
      AttendanceLoading() || AttendanceLoadError() => const SizedBox.shrink(),
    };
    final canPunch =
        !state.isWorking &&
        (state is AttendanceCheckedIn ||
            state is AttendanceCompleted ||
            (state is AttendanceNotCheckedIn && !isNoBranch));
    final button = state is AttendanceCompleted
        ? const FilledButton(onPressed: null, child: Text('Done for today'))
        : FilledButton.icon(
            onPressed: canPunch
                ? () {
                    if (uid == null) return;
                    final controller = ref.read(
                      attendanceControllerProvider.notifier,
                    );
                    if (state is AttendanceCheckedIn) {
                      controller.checkOut();
                    } else {
                      controller.checkIn();
                    }
                  }
                : null,
            icon: state.isWorking
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Icon(
                    state is AttendanceCheckedIn ? Icons.logout : Icons.login,
                  ),
            label: Text(
              state.isWorking
                  ? 'Getting your location...'
                  : state is AttendanceCheckedIn
                  ? 'Check out'
                  : 'Check in',
            ),
          );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        card,
        const SizedBox(height: 16),
        SizedBox(height: 56, child: button),
        if (state is AttendanceNotCheckedIn &&
            estimate.asData?.value is LocationEstimateAvailable &&
            !(estimate.asData!.value as LocationEstimateAvailable)
                .value
                .insideEstimate) ...[
          const SizedBox(height: 8),
          const Text(
            'Your location estimate is outside the branch radius. The server decides whether a punch is accepted.',
            textAlign: TextAlign.center,
          ),
        ],
        if (state is AttendanceNotCheckedIn && isNoBranch) ...[
          const SizedBox(height: 8),
          const Text(
            'No branch is assigned to you yet. Ask your admin.',
            textAlign: TextAlign.center,
          ),
        ],
      ],
    );
  }

  Widget _statusCard(
    BuildContext context, {
    required String title,
    required IconData icon,
    required List<Widget> children,
  }) => Card(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          Icon(icon, size: 36),
          const SizedBox(height: 12),
          Text(
            title,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleLarge,
          ),
          for (final child in children) ...[const SizedBox(height: 8), child],
        ],
      ),
    ),
  );

  Widget _buildDistanceCard(
    BuildContext context,
    AsyncValue<LocationEstimate> estimate,
    String? uid,
  ) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Distance estimate',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          estimate.when(
            loading: () => const Row(
              children: [
                SizedBox.square(
                  dimension: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                SizedBox(width: 8),
                Text('Getting your location...'),
              ],
            ),
            error: (_, _) => const Text('Could not load location estimate.'),
            data: (value) => switch (value) {
              LocationEstimateNoBranches() => const Text(
                'No branch is assigned to you yet. Ask your admin.',
              ),
              LocationEstimateUnavailable(:final reason) => Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(locationFailureMessage(reason)),
                  if (_hasSettingsAction(reason))
                    TextButton(
                      onPressed: () => ref
                          .read(locationServiceProvider)
                          .openSettings(reason),
                      child: Text(_settingsLabel(reason)),
                    ),
                ],
              ),
              LocationEstimateAvailable(:final value) => Text(
                'You are about ${formatDistance(value.distanceMeters)} from '
                '${value.branch.name} '
                '(${value.insideEstimate ? 'inside' : 'outside'}).',
              ),
            },
          ),
          const SizedBox(height: 8),
          Text(
            'This is an estimate only; the server makes the final decision.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: uid == null
                  ? null
                  : () {
                      ref.invalidate(employeeBranchesProvider(uid));
                      ref.invalidate(locationEstimateProvider(uid));
                    },
              icon: const Icon(Icons.my_location),
              label: const Text('Refresh location'),
            ),
          ),
        ],
      ),
    ),
  );

  Widget _buildFeedback(BuildContext context, AttendanceHomeState state) =>
      Card(
        color: Theme.of(context).colorScheme.errorContainer,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(state.feedback!),
              if (state.locationFailure case final reason?
                  when _hasSettingsAction(reason))
                TextButton(
                  onPressed: () =>
                      ref.read(locationServiceProvider).openSettings(reason),
                  child: Text(_settingsLabel(reason)),
                ),
            ],
          ),
        ),
      );

  bool _hasSettingsAction(LocationFailureReason reason) =>
      reason == LocationFailureReason.serviceDisabled ||
      reason == LocationFailureReason.permissionDeniedForever;

  String _settingsLabel(LocationFailureReason reason) =>
      reason == LocationFailureReason.serviceDisabled
      ? 'Open location settings'
      : 'Open app settings';

  String _formatDate(String date) {
    final parsed = DateTime.parse('${date}T00:00:00Z');
    const months = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];
    return '${months[parsed.month - 1]} ${parsed.day}, ${parsed.year}';
  }
}
