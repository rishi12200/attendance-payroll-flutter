import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/app_exception.dart';
import '../data/attendance_views_providers.dart';
import '../domain/attendance_helpers.dart';
import '../domain/attendance_views.dart';

class AdminFlaggedCheckinsScreen extends ConsumerStatefulWidget {
  const AdminFlaggedCheckinsScreen({super.key});

  @override
  ConsumerState<AdminFlaggedCheckinsScreen> createState() =>
      _AdminFlaggedCheckinsScreenState();
}

class _AdminFlaggedCheckinsScreenState
    extends ConsumerState<AdminFlaggedCheckinsScreen> {
  late DateTimeRange _range;

  String get _from => _dateString(_range.start);
  String get _to => _dateString(_range.end);
  ({String? from, String? to}) get _rangeKey => (from: _from, to: _to);

  @override
  void initState() {
    super.initState();
    final today = _istToday();
    _range = DateTimeRange(
      start: DateTime.utc(
        today.year,
        today.month,
        today.day,
      ).subtract(const Duration(days: 6)),
      end: DateTime.utc(today.year, today.month, today.day),
    );
  }

  @override
  Widget build(BuildContext context) {
    final flagged = ref.watch(flaggedCheckinsProvider(_rangeKey));
    return Scaffold(
      appBar: AppBar(
        title: const Text('Flagged check-ins'),
        actions: [
          IconButton(
            tooltip: 'Choose date range',
            onPressed: () => _chooseRange(context),
            icon: const Icon(Icons.date_range),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(flaggedCheckinsProvider(_rangeKey));
          await ref.read(flaggedCheckinsProvider(_rangeKey).future);
        },
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              '${formatIstDateLong('${_from}T05:30:00.000Z')} – '
              '${formatIstDateLong('${_to}T05:30:00.000Z')}',
            ),
            const SizedBox(height: 12),
            flagged.when(
              loading: () => const SizedBox(
                height: 220,
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (error, _) => _FlaggedError(
                message: _errorMessage(error),
                onRetry: () =>
                    ref.invalidate(flaggedCheckinsProvider(_rangeKey)),
              ),
              data: (items) => items.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.symmetric(vertical: 36),
                      child: Center(
                        child: Text('No flagged check-ins in this date range.'),
                      ),
                    )
                  : Column(
                      children: [
                        for (final item in items)
                          Card(child: _FlaggedCheckinTile(item: item)),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _chooseRange(BuildContext context) async {
    final range = await showDateRangePicker(
      context: context,
      initialDateRange: _range,
      firstDate: DateTime.utc(2000),
      lastDate: DateTime.utc(2100),
      helpText: 'Choose up to 31 days',
    );
    if (range == null || !context.mounted) return;
    final inclusiveDays = range.end.difference(range.start).inDays + 1;
    if (inclusiveDays > 31) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Choose a range of 31 days or fewer.')),
      );
      return;
    }
    setState(() => _range = range);
  }
}

class _FlaggedCheckinTile extends StatelessWidget {
  const _FlaggedCheckinTile({required this.item});

  final FlaggedCheckin item;

  @override
  Widget build(BuildContext context) => ListTile(
    title: Text(item.name),
    subtitle: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('${item.empCode} · ${_readableReason(item.rejectReason)}'),
        Text(
          '${formatIstDateLong('${item.date}T05:30:00.000Z')} '
          '${formatIstTime(item.serverTime)}',
        ),
        if (item.nearestBranchName != null)
          Text(
            '${_formatDistance(item.distanceMeters)} '
            'from ${item.nearestBranchName}',
          ),
      ],
    ),
    trailing: Text(item.type == 'out' ? 'Check-out' : 'Check-in'),
  );
}

String _readableReason(String reason) => switch (reason) {
  'OUTSIDE_GEOFENCE' => 'Outside branch geofence',
  'ACCURACY_TOO_LOW' => 'GPS accuracy too low',
  'MOCK_LOCATION' => 'Mock location',
  'NO_BRANCH_ASSIGNED' => 'No branch assigned',
  _ => reason,
};

String _formatDistance(double? meters) {
  if (meters == null) return 'Distance unavailable';
  if (meters < 1000) return '${meters.round()} m';
  return '${(meters / 1000).toStringAsFixed(1)} km';
}

DateTime _istToday() {
  final date = istDateOf(DateTime.now().toUtc().toIso8601String());
  return DateTime.parse('${date}T00:00:00Z');
}

String _dateString(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-'
    '${date.month.toString().padLeft(2, '0')}-'
    '${date.day.toString().padLeft(2, '0')}';

class _FlaggedError extends StatelessWidget {
  const _FlaggedError({required this.message, required this.onRetry});

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

String _errorMessage(Object error) => switch (error) {
  AppException(:final message) => message,
  _ => 'Could not load flagged check-ins. Please try again.',
};
