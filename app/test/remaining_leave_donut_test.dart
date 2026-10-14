import 'package:app/features/leave/domain/leave_type.dart';
import 'package:app/features/leave/presentation/remaining_leave_donut.dart';
import 'package:app/features/leave/presentation/remaining_leave_donut_painter.dart';
import 'package:app/features/leave/presentation/remaining_leave_palette.dart';
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
      label: '$year',
      startDate: '$year-01-01',
      endDate: '$year-12-31',
      today: '$year-06-01',
      types: types,
    );

Widget _app(
  LeaveBalance balance, {
  double textScale = 1,
  Size size = const Size(400, 800),
}) => MaterialApp(
  home: MediaQuery(
    data: MediaQueryData(size: size, textScaler: TextScaler.linear(textScale)),
    child: Scaffold(
      body: ListView(children: [RemainingLeaveDonut(balance: balance)]),
    ),
  ),
);

void main() {
  test('fixed palette has eight distinct colors and cycles', () {
    expect(remainingLeavePalette.toSet(), hasLength(8));
    expect(remainingLeaveColor(8), remainingLeaveColor(0));
  });

  testWidgets('lists remaining segments in order and displays totals', (
    tester,
  ) async {
    final balance = _balanceYear([
      _balance('casual', 'Casual Leave', 4),
      _balance('sick', 'Sick Leave', 8),
      _balance('half', 'Half Day', .5),
      _balance('unlimited', 'Unpaid Leave', null),
      _balance('zero', 'Used Leave', 0),
      _balance('negative', 'Reduced Quota', -1),
    ]);
    await tester.pumpWidget(_app(balance));

    expect(find.text('12.5'), findsOneWidget);
    expect(find.text('days left'), findsOneWidget);
    expect(find.text('Casual Leave'), findsOneWidget);
    expect(find.text('Sick Leave'), findsOneWidget);
    expect(find.text('Half Day'), findsOneWidget);
    expect(find.text('4 days'), findsOneWidget);
    expect(find.text('8 days'), findsOneWidget);
    expect(find.text('0.5 day'), findsOneWidget);
    expect(find.text('Unpaid Leave'), findsNothing);
    expect(find.text('Used Leave'), findsNothing);
    expect(find.text('Reduced Quota'), findsNothing);
    expect(
      find.text('Types with no limit are not shown in this chart.'),
      findsOneWidget,
    );
    expect(find.textContaining('%'), findsNothing);

    final painter =
        tester
                .widget<CustomPaint>(
                  find.byKey(const ValueKey('remaining-leave-donut')),
                )
                .painter!
            as RemainingLeaveDonutPainter;
    expect(painter.labelValues, ['4', '8']);
    expect(painter.segments.map((segment) => segment.name), [
      'Casual Leave',
      'Sick Leave',
      'Half Day',
    ]);
  });

  testWidgets('omits the unlimited note when there are no unlimited types', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(_balanceYear([_balance('casual', 'Casual Leave', 2)])),
    );
    expect(
      find.text('Types with no limit are not shown in this chart.'),
      findsNothing,
    );
  });

  testWidgets('shows a grey zero ring for limited types with no days left', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        _balanceYear([
          _balance('zero', 'Used Leave', 0),
          _balance('negative', 'Reduced Quota', -1),
          _balance('unlimited', 'Unpaid Leave', null),
        ]),
      ),
    );
    expect(find.text('0'), findsOneWidget);
    expect(find.text('days left'), findsOneWidget);
    expect(find.text('No leave days remaining.'), findsOneWidget);
    expect(
      find.text('Types with no limit are not shown in this chart.'),
      findsOneWidget,
    );
    final painter =
        tester
                .widget<CustomPaint>(
                  find.byKey(const ValueKey('remaining-leave-donut')),
                )
                .painter!
            as RemainingLeaveDonutPainter;
    expect(painter.hasRemainingDays, isFalse);
    expect(painter.segments, isEmpty);

    await tester.pumpWidget(
      _app(
        _balanceYear([
          _balance('zero', 'Used Leave', 0),
          _balance('negative', 'Reduced Quota', -1),
        ]),
      ),
    );
    expect(find.text('No leave days remaining.'), findsOneWidget);
    expect(
      find.text('Types with no limit are not shown in this chart.'),
      findsNothing,
    );
  });

  testWidgets('shows no chart when all types are unlimited or none exist', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(_balanceYear([_balance('unlimited', 'Unpaid Leave', null)])),
    );
    expect(find.byKey(const ValueKey('remaining-leave-donut')), findsNothing);

    await tester.pumpWidget(_app(_balanceYear([])));
    expect(find.byKey(const ValueKey('remaining-leave-donut')), findsNothing);
  });

  testWidgets('keeps a segment color index when another type reaches zero', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        _balanceYear([
          _balance('first', 'First Leave', 2),
          _balance('middle', 'Middle Leave', 1),
          _balance('last', 'Last Leave', 3),
        ]),
      ),
    );
    var painter =
        tester
                .widget<CustomPaint>(
                  find.byKey(const ValueKey('remaining-leave-donut')),
                )
                .painter!
            as RemainingLeaveDonutPainter;
    expect(painter.segments.last.colorIndex, 2);
    final before = remainingLeaveColor(painter.segments.last.colorIndex);

    await tester.pumpWidget(
      _app(
        _balanceYear([
          _balance('first', 'First Leave', 2),
          _balance('middle', 'Middle Leave', 0),
          _balance('last', 'Last Leave', 3),
        ]),
      ),
    );
    painter =
        tester
                .widget<CustomPaint>(
                  find.byKey(const ValueKey('remaining-leave-donut')),
                )
                .painter!
            as RemainingLeaveDonutPainter;
    expect(painter.segments.last.colorIndex, 2);
    expect(remainingLeaveColor(painter.segments.last.colorIndex), before);
  });

  testWidgets('provides a combined semantics label for segments and total', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        _balanceYear([
          _balance('casual', 'Casual Leave', 4),
          _balance('sick', 'Sick Leave', 8),
        ]),
      ),
    );
    final semantics = tester.widget<Semantics>(
      find
          .ancestor(
            of: find.byKey(const ValueKey('remaining-leave-donut')),
            matching: find.byType(Semantics),
          )
          .first,
    );
    expect(
      semantics.properties.label,
      'Remaining leave: Casual Leave 4 days, Sick Leave 8 days. Total 12 days left.',
    );
  });

  testWidgets('scales down center labels at large system text size', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        _balanceYear([_balance('sick', 'Sick Leave', 7.5)]),
        textScale: 2,
        size: const Size(250, 700),
      ),
    );
    expect(tester.takeException(), isNull);
    expect(find.text('7.5'), findsOneWidget);
    expect(find.text('days left'), findsOneWidget);
  });
}
