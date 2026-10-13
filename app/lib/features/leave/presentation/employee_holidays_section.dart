import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../attendance/data/attendance_views_providers.dart';
import '../../attendance/domain/holiday_helpers.dart';

class EmployeeHolidaysSection extends ConsumerStatefulWidget {
  const EmployeeHolidaysSection({super.key});

  @override
  ConsumerState<EmployeeHolidaysSection> createState() =>
      _EmployeeHolidaysSectionState();
}

class _EmployeeHolidaysSectionState
    extends ConsumerState<EmployeeHolidaysSection> {
  int? _year;

  @override
  Widget build(BuildContext context) => ref
      .watch(attendanceServerTodayProvider)
      .when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => _Error(
          message: 'Could not load holidays. Please retry.',
          onRetry: () => ref.invalidate(attendanceServerTodayProvider),
        ),
        data: (today) {
          final currentYear = int.parse(today.substring(0, 4));
          final year = _year ?? currentYear;
          return Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(
                    tooltip: 'Previous year',
                    onPressed: year > 2000
                        ? () => setState(() => _year = year - 1)
                        : null,
                    icon: const Icon(Icons.chevron_left),
                  ),
                  Text('$year', style: Theme.of(context).textTheme.titleMedium),
                  IconButton(
                    tooltip: 'Next year',
                    onPressed: year < 2100
                        ? () => setState(() => _year = year + 1)
                        : null,
                    icon: const Icon(Icons.chevron_right),
                  ),
                ],
              ),
              Expanded(child: _holidayList('$year', today)),
            ],
          );
        },
      );

  Widget _holidayList(String year, String today) {
    final holidays = ref.watch(myHolidaysProvider(year));
    return holidays.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, _) => _Error(
        message: 'Could not load holidays. Please retry.',
        onRetry: () => ref.invalidate(myHolidaysProvider(year)),
      ),
      data: (items) {
        final sorted = [...items]..sort((a, b) => a.date.compareTo(b.date));
        final next = sorted
            .where((item) => item.date.compareTo(today) > 0)
            .firstOrNull;
        return RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(myHolidaysProvider(year));
            await ref.read(myHolidaysProvider(year).future);
          },
          child: sorted.isEmpty
              ? ListView(
                  children: [
                    const SizedBox(height: 120),
                    Center(child: Text('No holidays for $year')),
                  ],
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
                  itemCount: sorted.length,
                  itemBuilder: (context, index) {
                    final holiday = sorted[index];
                    final isToday = holiday.date == today;
                    final isPast = holiday.date.compareTo(today) < 0;
                    final isNext = identical(holiday, next);
                    return Opacity(
                      opacity: isPast ? 0.55 : 1,
                      child: Card(
                        color: isToday
                            ? Theme.of(context).colorScheme.primaryContainer
                            : null,
                        child: ListTile(
                          title: Text(holiday.name),
                          subtitle: Text(
                            '${readableHolidayDate(holiday.date)}\n${employeeHolidayScopeLabel(holiday)}',
                          ),
                          isThreeLine: true,
                          trailing: isToday
                              ? const Chip(label: Text('Today'))
                              : isNext
                              ? const Chip(label: Text('Upcoming'))
                              : null,
                        ),
                      ),
                    );
                  },
                ),
        );
      },
    );
  }
}

class _Error extends StatelessWidget {
  const _Error({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(message),
        TextButton(onPressed: onRetry, child: const Text('Retry')),
      ],
    ),
  );
}
