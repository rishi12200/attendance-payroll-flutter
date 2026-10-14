import 'package:app/features/leave/domain/leave_type.dart';
import 'package:app/features/leave/domain/remaining_leave_slices.dart';
import 'package:app/features/leave/presentation/remaining_leave_chart.dart';
import 'package:app/features/leave/presentation/remaining_leave_palette.dart';
import 'package:app/features/leave/presentation/remaining_leave_pie_painter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

BalanceType _balance(String id, String name, double? remaining) => BalanceType(
  leaveTypeId: id,
  name: name,
  code: id,
  paid: true,
  allowHalfDay: true,
  quota: 10,
  used: 0,
  pending: 0,
  remaining: remaining,
);

LeaveBalance _balanceYear(List<BalanceType> types, {int year = 2026}) =>
    LeaveBalance(
      year: year,
      label: '$year leave year',
      startDate: '$year-01-01',
      endDate: '$year-12-31',
      today: '$year-06-01',
      types: types,
    );

Widget _app(LeaveBalance balance) => MaterialApp(
  home: Scaffold(
    body: ListView(
      children: [
        RemainingLeaveChartCard(
          balance: balance,
          sliceData: buildRemainingSlices(balanceTypes: balance.types),
        ),
      ],
    ),
  ),
);

void main() {
  test('palette has eight distinct colors and cycles by original index', () {
    final palette = remainingLeavePalette(ThemeData.light().colorScheme);
    expect(palette.toSet(), hasLength(8));
    expect(
      remainingLeaveColor(8, ThemeData.light().colorScheme),
      remainingLeaveColor(0, ThemeData.light().colorScheme),
    );
  });

  testWidgets('shows year, readable legend, days, and semantic pie label', (
    tester,
  ) async {
    final balance = _balanceYear([
      _balance('sick', 'Sick Leave', 6.5),
      _balance('casual', 'Casual Leave', 1.5),
      _balance('unlimited', 'Unpaid Leave', null),
    ]);
    await tester.pumpWidget(_app(balance));

    expect(find.text('Remaining leave days'), findsOneWidget);
    expect(find.text('2026 leave year'), findsOneWidget);
    expect(find.text('Sick Leave'), findsOneWidget);
    expect(find.text('6.5 days'), findsOneWidget);
    expect(find.text('1.5 days'), findsOneWidget);
    expect(
      find.text('Not in the chart: Unpaid Leave (no limit)'),
      findsOneWidget,
    );
    expect(find.text('Days left after pending requests.'), findsOneWidget);
    expect(find.textContaining('%'), findsNothing);
    final pieSemantics = tester.widget<Semantics>(
      find
          .ancestor(
            of: find.byKey(const ValueKey('remaining-leave-pie')),
            matching: find.byType(Semantics),
          )
          .first,
    );
    expect(
      pieSemantics.properties.label,
      'Remaining leave days for 2026 leave year: Sick Leave, 6.5 days; Casual Leave, 1.5 days',
    );

    final painter =
        tester
                .widget<CustomPaint>(
                  find.byKey(const ValueKey('remaining-leave-pie')),
                )
                .painter!
            as RemainingLeavePiePainter;
    expect(painter.labelValues, ['6.5', '1.5']);
  });

  testWidgets('shows empty text and exclusions when no slices remain', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        _balanceYear([
          _balance('zero', 'Zero Leave', 0),
          _balance('unlimited', 'Unpaid Leave', null),
        ]),
      ),
    );
    expect(find.text('No remaining leave days to show.'), findsOneWidget);
    expect(
      find.text(
        'Not in the chart: Unpaid Leave (no limit), Zero Leave (0 left)',
      ),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('remaining-leave-pie')), findsNothing);
  });

  testWidgets('single slice fills chart without a gap and label data updates', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(_balanceYear([_balance('annual', 'Annual Leave', .5)])),
    );
    final painter =
        tester
                .widget<CustomPaint>(
                  find.byKey(const ValueKey('remaining-leave-pie')),
                )
                .painter!
            as RemainingLeavePiePainter;
    expect(painter.slices.single.sweepRadians, 2 * 3.141592653589793);
    expect(painter.labelValues, ['0.5']);
    expect(find.textContaining('Not in the chart:'), findsNothing);

    await tester.pumpWidget(
      _app(_balanceYear([_balance('annual', 'Annual Leave', .5)], year: 2025)),
    );
    expect(find.text('2025 leave year'), findsOneWidget);
  });
}
