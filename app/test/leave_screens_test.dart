import 'dart:async';

import 'package:app/core/api/app_exception.dart';
import 'package:app/features/attendance/domain/attendance_controller.dart';
import 'package:app/features/attendance/data/attendance_views_providers.dart';
import 'package:app/features/attendance/domain/attendance_views.dart';
import 'package:app/features/attendance/data/attendance_views_repository.dart';
import 'package:app/features/leave/data/leave_providers.dart';
import 'package:app/features/leave/data/leave_repository.dart';
import 'package:app/features/leave/domain/leave_form_validation.dart';
import 'package:app/features/leave/domain/leave_helpers.dart';
import 'package:app/features/leave/domain/leave_request.dart';
import 'package:app/features/leave/domain/leave_type.dart';
import 'package:app/features/leave/presentation/admin_leave_requests_screen.dart';
import 'package:app/features/leave/presentation/admin_leave_types_screen.dart';
import 'package:app/features/leave/presentation/apply_leave_screen.dart';
import 'package:app/features/leave/presentation/my_leave_requests_screen.dart';
import 'package:app/features/leave/presentation/employee_leave_section.dart';
import 'package:app/features/employees/data/employees_providers.dart';
import 'package:app/features/employees/domain/employee.dart';
import 'package:app/features/employees/domain/salary_revision.dart';
import 'package:app/features/employees/presentation/employee_detail_screen.dart';
import 'package:app/features/branches/data/branches_providers.dart';
import 'package:app/features/branches/domain/branch.dart';
import 'package:app/features/leave/presentation/pending_leave_badge.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

class _FakeAttendanceController extends AttendanceController {
  @override
  AttendanceHomeState build() => const AttendanceNotCheckedIn(
    today: '2026-10-12',
    serverTime: '2026-10-12T03:30:00.000Z',
  );
  @override
  Future<void> refresh({bool allowWhileWorking = false}) async {
    state = const AttendanceNotCheckedIn(
      today: '2026-10-12',
      serverTime: '2026-10-12T03:30:00.000Z',
    );
  }
}

class _FakeLeaveRepository implements LeaveRepository {
  _FakeLeaveRepository([List<LeaveRequest>? initial])
    : requests = initial ?? [];
  final List<LeaveRequest> requests;
  int mineCalls = 0;
  int adminCalls = 0;
  int cancelCalls = 0;
  int applyCalls = 0;
  int decideCalls = 0;
  int balanceCalls = 0;
  String? lastStatus;
  String? lastEmpId;
  int? lastAdminCount;
  int? lastBalanceYear;
  String? lastBalanceEmpId;
  AppException? applyError;
  AppException? cancelError;
  AppException? decisionError;
  AppException? mineError;
  AppException? adminError;
  AppException? typeError;
  AppException? typeWriteError;
  AppException? balanceError;
  List<LeaveType> availableTypes = const [
    LeaveType(
      id: 'sick',
      name: 'Sick Leave',
      code: 'SL',
      paid: true,
      annualQuotaDays: 8,
      allowHalfDay: true,
    ),
    LeaveType(
      id: 'casual',
      name: 'Casual Leave',
      code: 'CL',
      paid: true,
      annualQuotaDays: 8,
      allowHalfDay: true,
    ),
    LeaveType(
      id: 'unpaid',
      name: 'Unpaid Leave',
      code: 'UL',
      paid: false,
      annualQuotaDays: null,
      allowHalfDay: true,
      system: true,
    ),
  ];
  LeaveRequest? decisionResult;
  Completer<List<LeaveRequest>>? mineCompleter;
  Completer<List<LeaveRequest>>? adminCompleter;
  String? lastAppliedType;
  String? lastSession;
  String? lastNote;
  Map<String, Object?>? createdType;

  @override
  Future<LeaveRequest> apply({
    required String leaveTypeId,
    required String fromDate,
    required String toDate,
    required String reason,
    String session = 'full',
  }) async {
    applyCalls++;
    if (applyError != null) throw applyError!;
    final created = _request(
      fromDate: fromDate,
      toDate: toDate,
      reason: reason,
      leaveTypeId: leaveTypeId,
      session: session,
    );
    lastAppliedType = leaveTypeId;
    lastSession = session;
    requests.insert(0, created);
    return created;
  }

  @override
  Future<List<LeaveRequest>> myRequests(String status) async {
    mineCalls++;
    if (mineError != null) throw mineError!;
    if (mineCompleter != null) return mineCompleter!.future;
    final result = status == 'all'
        ? List.of(requests)
        : requests.where((item) => item.status.name == status).toList();
    lastAdminCount = result.length;
    return result;
  }

  @override
  Future<LeaveRequest> cancel(String id) async {
    cancelCalls++;
    if (cancelError != null) throw cancelError!;
    final index = requests.indexWhere((item) => item.id == id);
    final cancelled = _request(status: LeaveStatus.cancelled);
    requests[index] = cancelled;
    return cancelled;
  }

  @override
  Future<List<LeaveRequest>> adminList(String status, {String? empId}) async {
    adminCalls++;
    lastStatus = status;
    lastEmpId = empId;
    if (adminError != null) throw adminError!;
    if (adminCompleter != null) return adminCompleter!.future;
    return status == 'all'
        ? List.of(requests)
        : requests.where((item) => item.status.name == status).toList();
  }

  @override
  Future<LeaveRequest> get(String id) async =>
      requests.firstWhere((item) => item.id == id);
  @override
  Future<LeaveRequest> decide({
    required String id,
    required String decision,
    String? note,
  }) async {
    decideCalls++;
    lastNote = note;
    if (decisionError != null) throw decisionError!;
    final result =
        decisionResult ??
        _request(
          status: decision == 'approved'
              ? LeaveStatus.approved
              : LeaveStatus.rejected,
          note: note,
        );
    final index = requests.indexWhere((item) => item.id == id);
    if (index >= 0) requests[index] = result;
    return result;
  }

  @override
  Future<List<LeaveType>> listLeaveTypes({String status = 'all'}) async {
    if (typeError != null) throw typeError!;
    return availableTypes
        .where((item) => status == 'all' || item.status == status)
        .toList();
  }

  @override
  Future<LeaveBalance> getBalance({int? year, String? empId}) async {
    balanceCalls++;
    lastBalanceYear = year;
    lastBalanceEmpId = empId;
    if (balanceError != null) throw balanceError!;
    final selectedYear = year ?? 2026;
    return LeaveBalance(
      year: selectedYear,
      label: '$selectedYear',
      startDate: '$selectedYear-01-01',
      endDate: '$selectedYear-12-31',
      today: '2026-10-12',
      types: const [
        BalanceType(
          leaveTypeId: 'sick',
          name: 'Sick Leave',
          code: 'SL',
          paid: true,
          allowHalfDay: true,
          quota: 8,
          used: 1,
          pending: 0.5,
          remaining: 6.5,
        ),
        BalanceType(
          leaveTypeId: 'unpaid',
          name: 'Unpaid Leave',
          code: 'UL',
          paid: false,
          allowHalfDay: true,
          quota: null,
          used: 0.5,
          pending: 0,
          remaining: null,
        ),
      ],
    );
  }

  @override
  Future<LeaveType> createLeaveType(Map<String, Object?> values) async {
    if (typeWriteError != null) throw typeWriteError!;
    createdType = Map.of(values);
    return availableTypes.first;
  }

  @override
  Future<LeaveType> updateLeaveType(
    String id,
    Map<String, Object?> changes,
  ) async {
    if (typeWriteError != null) throw typeWriteError!;
    return listLeaveTypes().then((v) => v.first);
  }

  @override
  Future<LeaveType> deactivateLeaveType(String id) async {
    if (typeWriteError != null) throw typeWriteError!;
    return listLeaveTypes().then((v) => v.first);
  }

  @override
  Future<LeaveType> reactivateLeaveType(String id) async {
    if (typeWriteError != null) throw typeWriteError!;
    return listLeaveTypes().then((v) => v.first);
  }
}

LeaveRequest _request({
  String id = 'leave-1',
  String fromDate = '2026-10-12',
  String toDate = '2026-10-13',
  String reason = 'Family event',
  LeaveStatus status = LeaveStatus.pending,
  String? leaveTypeId = 'sick',
  String? leaveTypeName = 'Sick Leave',
  bool? paid = true,
  String session = 'full',
  double? requestedDays,
  double? writtenDays,
  String? note,
  List<String> written = const [],
  List<SkippedDate> skipped = const [],
  bool noDaysWritten = false,
  String name = 'Asha',
}) => LeaveRequest(
  id: id,
  empId: 'emp-1',
  fromDate: fromDate,
  toDate: toDate,
  reason: reason,
  status: status,
  createdAt: '2026-10-12T00:00:00.000Z',
  updatedAt: '2026-10-12T00:00:00.000Z',
  leaveTypeId: leaveTypeId,
  leaveTypeName: leaveTypeName,
  paid: paid,
  session: session,
  requestedDays: requestedDays ?? leaveDayCount(fromDate, toDate).toDouble(),
  writtenDays: writtenDays,
  decidedBy: status == LeaveStatus.pending ? null : 'admin-1',
  decidedAt: status == LeaveStatus.pending ? null : '2026-10-12T00:00:00.000Z',
  decisionNote: note,
  writtenDates: written,
  skippedDates: skipped,
  noDaysWritten: noDaysWritten,
  empCode: id == 'leave-2' ? 'EMP002' : 'EMP001',
  name: name,
  designation: 'Associate',
);

Widget _app(Widget child, _FakeLeaveRepository repository) => ProviderScope(
  overrides: [
    leaveRepositoryProvider.overrideWithValue(repository),
    attendanceControllerProvider.overrideWith(_FakeAttendanceController.new),
    attendanceServerTodayProvider.overrideWith((ref) async => '2026-10-13'),
    myHolidaysProvider('2026').overrideWith(
      (ref) async => const [
        AttendanceHoliday(
          id: 'holiday',
          date: '2026-10-13',
          name: 'Founders day',
        ),
      ],
    ),
  ],
  child: MaterialApp(home: child),
);

Widget _routerApp(_FakeLeaveRepository repository) {
  final router = GoRouter(
    initialLocation: '/employee/leave',
    routes: [
      GoRoute(
        path: '/employee/leave',
        builder: (_, _) => const MyLeaveRequestsScreen(),
      ),
      GoRoute(
        path: '/employee/leave/apply',
        builder: (_, _) => const ApplyLeaveScreen(),
      ),
    ],
  );
  return ProviderScope(
    overrides: [
      leaveRepositoryProvider.overrideWithValue(repository),
      attendanceControllerProvider.overrideWith(_FakeAttendanceController.new),
    ],
    child: MaterialApp.router(routerConfig: router),
  );
}

class _EmployeeHolidayRepository extends Fake
    implements AttendanceViewsRepository {
  String? requestedYear;
  String? requestedBranchId;
  Object? error;

  @override
  Future<List<AttendanceHoliday>> listHolidays(
    String year, {
    String? branchId,
  }) async {
    requestedYear = year;
    requestedBranchId = branchId;
    if (error != null) throw error!;
    return const [
      AttendanceHoliday(
        id: 'h1',
        date: '2026-10-20',
        weekday: 'Tuesday',
        name: 'Founders Day',
      ),
    ];
  }
}

const _detailEmployee = Employee(
  uid: 'emp-1',
  empCode: 'EMP001',
  name: 'Asha',
  email: 'asha@example.com',
  role: 'employee',
  status: EmployeeStatus.active,
  doj: '2024-01-01',
  createdAt: '2024-01-01T00:00:00.000Z',
  updatedAt: '2024-01-01T00:00:00.000Z',
  primaryBranchId: 'branch-1',
);

Widget _employeeDetailApp(
  _FakeLeaveRepository leaveRepository, {
  required Employee employee,
  _EmployeeHolidayRepository? holidayRepository,
}) => ProviderScope(
  key: ValueKey(employee.uid),
  overrides: [
    leaveRepositoryProvider.overrideWithValue(leaveRepository),
    employeeProvider(employee.uid).overrideWith((ref) async => employee),
    salaryHistoryProvider(employee.uid)
        .overrideWith((ref) async => <SalaryRevision>[]),
    branchesProvider('active').overrideWith((ref) async => const <Branch>[]),
    attendanceServerTodayProvider.overrideWith((ref) async => '2026-10-14'),
    if (holidayRepository != null)
      attendanceViewsRepositoryProvider.overrideWithValue(holidayRepository),
  ],
  child: MaterialApp(home: EmployeeDetailScreen(id: employee.uid)),
);

Future<void> _pickTwoLeaveDays(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1000, 1000);
  tester.view.devicePixelRatio = 1;
  await tester.pump();
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.tap(find.byKey(const ValueKey('leave-type-picker')));
  await tester.pumpAndSettle();
  await tester.tap(find.textContaining('Sick Leave').last);
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const ValueKey('leave-date-range-button')));
  await tester.pumpAndSettle();
  await tester.tap(find.text('12').last);
  await tester.pumpAndSettle();
  await tester.tap(find.text('13').last);
  await tester.pumpAndSettle();
  await tester.tap(find.text('Save'));
  await tester.pumpAndSettle();
}

Future<void> _pickSingleLeaveDay(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1000, 1000);
  tester.view.devicePixelRatio = 1;
  await tester.pump();
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.tap(find.byKey(const ValueKey('leave-type-picker')));
  await tester.pumpAndSettle();
  await tester.tap(find.textContaining('Sick Leave').last);
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const ValueKey('leave-date-range-button')));
  await tester.pumpAndSettle();
  await tester.tap(find.text('12').last);
  await tester.pumpAndSettle();
  await tester.tap(find.text('12').last);
  await tester.pumpAndSettle();
  final save = find.text('Save');
  if (save.evaluate().isNotEmpty) await tester.tap(save);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('admin leave type form validates and normalizes new types', (
    tester,
  ) async {
    final repository = _FakeLeaveRepository();
    final router = GoRouter(
      initialLocation: '/leave-types/new',
      routes: [
        GoRoute(
          path: '/',
          builder: (_, _) => const Scaffold(),
          routes: [
            GoRoute(
              path: 'leave-types/new',
              builder: (_, _) => const AdminLeaveTypeFormScreen(),
            ),
          ],
        ),
      ],
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [leaveRepositoryProvider.overrideWithValue(repository)],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('leave-type-name')),
      'Sick',
    );
    await tester.enterText(find.byKey(const ValueKey('leave-type-code')), 'sl');
    await tester.enterText(
      find.byKey(const ValueKey('leave-type-quota')),
      '0.3',
    );
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('save-leave-type')),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.byKey(const ValueKey('save-leave-type')));
    await tester.pumpAndSettle();
    expect(find.text('Enter 0.5 to 366 in 0.5 day steps.'), findsOneWidget);
    await tester.ensureVisible(find.byKey(const ValueKey('leave-type-quota')));
    await tester.enterText(
      find.byKey(const ValueKey('leave-type-quota')),
      '0.5',
    );
    repository.typeWriteError = const AppException(
      code: 'LEAVE_TYPE_CODE_EXISTS',
      message: 'Conflict',
      details: {},
    );
    await tester.ensureVisible(find.byKey(const ValueKey('save-leave-type')));
    await tester.tap(find.byKey(const ValueKey('save-leave-type')));
    await tester.pumpAndSettle();
    expect(find.text('This code is already used.'), findsOneWidget);
    repository.typeWriteError = null;
    await tester.pump(const Duration(seconds: 5));
    await tester.ensureVisible(find.byKey(const ValueKey('save-leave-type')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('save-leave-type')));
    await tester.pumpAndSettle();
    expect(repository.createdType?['code'], 'SL');
    expect(repository.createdType?['annualQuotaDays'], 0.5);
  });

  testWidgets('admin leave type list filters types and shows system badges', (
    tester,
  ) async {
    final repository = _FakeLeaveRepository()
      ..availableTypes = [
        ..._FakeLeaveRepository().availableTypes,
        const LeaveType(
          id: 'legacy-paid',
          name: 'Paid Leave',
          code: 'PL',
          paid: true,
          annualQuotaDays: null,
          allowHalfDay: false,
          status: 'inactive',
          system: true,
        ),
      ];
    await tester.pumpWidget(
      ProviderScope(
        overrides: [leaveRepositoryProvider.overrideWithValue(repository)],
        child: const MaterialApp(home: AdminLeaveTypesScreen()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('System'), findsNWidgets(2));
    expect(find.text('Half days'), findsNWidgets(3));
    repository.typeWriteError = const AppException(
      code: 'LEAVE_TYPE_IN_USE',
      message: 'Conflict',
      details: {'pendingCount': 2},
    );
    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey('leave-type-sick')),
        matching: find.byType(PopupMenuButton<String>),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Deactivate'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Deactivate'));
    await tester.pumpAndSettle();
    expect(
      find.text(
        '2 pending requests use this type. Decide or cancel them first.',
      ),
      findsOneWidget,
    );
    await tester.tap(find.text('Inactive').first);
    await tester.pumpAndSettle();
    expect(find.text('Paid Leave (PL)'), findsOneWidget);
    expect(find.text('Sick Leave (SL)'), findsNothing);
    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey('leave-type-legacy-paid')),
        matching: find.byType(PopupMenuButton<String>),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Reactivate'), findsNothing);
  });

  testWidgets(
    'system leave type form locks paid fields and shows legacy notice',
    (tester) async {
      const legacy = LeaveType(
        id: 'legacy-paid',
        name: 'Paid Leave',
        code: 'PL',
        paid: true,
        annualQuotaDays: null,
        allowHalfDay: false,
        status: 'inactive',
        system: true,
      );
      final repository = _FakeLeaveRepository();
      final router = GoRouter(
        initialLocation: '/leave-types/edit',
        routes: [
          GoRoute(
            path: '/',
            builder: (_, _) => const Scaffold(),
            routes: [
              GoRoute(
                path: 'leave-types/edit',
                builder: (_, _) => const AdminLeaveTypeFormScreen(type: legacy),
              ),
            ],
          ),
        ],
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [leaveRepositoryProvider.overrideWithValue(repository)],
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.text(
          "This is a system type. Its paid status and quota can't be changed.",
        ),
        findsOneWidget,
      );
      expect(
        find.text("Only used to display old requests. It can't be activated."),
        findsOneWidget,
      );
      expect(
        tester
            .widget<SwitchListTile>(
              find.widgetWithText(SwitchListTile, 'Paid leave'),
            )
            .onChanged,
        isNull,
      );
    },
  );

  testWidgets(
    'Leave tab balance shows decimal data and clamps year navigation',
    (tester) async {
      final repository = _FakeLeaveRepository();
      await tester.pumpWidget(_app(const MyLeaveRequestsScreen(), repository));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Balance'));
      await tester.pumpAndSettle();
      expect(find.text('Remaining leave days'), findsOneWidget);
      expect(find.text('2026'), findsNWidgets(2));
      expect(find.text('6.5 days'), findsOneWidget);
      expect(find.text('Days left after pending requests.'), findsOneWidget);
      expect(find.textContaining('%'), findsNothing);
      expect(
        find.text('Not in the chart: Unpaid Leave (no limit)'),
        findsOneWidget,
      );
      expect(
        find.text('Pending requests are reserved from your balance.'),
        findsOneWidget,
      );
      await tester.ensureVisible(find.text('Quota: 8 days'));
      await tester.pumpAndSettle();
      expect(find.text('Quota: 8 days'), findsOneWidget);
      expect(find.text('Used: 1 day'), findsOneWidget);
      expect(find.text('Pending: 0.5 day'), findsOneWidget);
      expect(find.text('Remaining: 6.5 days'), findsOneWidget);
      await tester.ensureVisible(find.text('Quota: No limit'));
      await tester.pumpAndSettle();
      expect(find.text('Quota: No limit'), findsOneWidget);
      expect(find.text('Used: 0.5 day'), findsOneWidget);
      expect(find.text('Pending: 0 days'), findsOneWidget);
      expect(find.text('Remaining: No limit'), findsOneWidget);
      expect(find.byKey(const ValueKey('apply-leave-button')), findsNothing);
      await tester.drag(find.byType(ListView).last, const Offset(0, 1000));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Previous leave year'));
      await tester.pumpAndSettle();
      expect(find.text('2025'), findsNWidgets(2));
      expect(find.text('Remaining leave days'), findsOneWidget);
      await tester.tap(find.byTooltip('Previous leave year'));
      await tester.pumpAndSettle();
      expect(find.text('2025'), findsNWidgets(2));
      await tester.tap(find.byTooltip('Next leave year'));
      await tester.pumpAndSettle();
      expect(find.text('2026'), findsNWidgets(2));
    },
  );

  testWidgets('apply type picker shows paid labels and remaining or no limit', (
    tester,
  ) async {
    final repository = _FakeLeaveRepository();
    await tester.pumpWidget(_app(const ApplyLeaveScreen(), repository));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('leave-type-picker')));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Sick Leave · SL · Paid · 6.5 days left'),
      findsOneWidget,
    );
    expect(
      find.textContaining('Unpaid Leave · UL · Unpaid · No limit'),
      findsOneWidget,
    );
  });

  testWidgets('half-day session is available for one date and applies as 0.5', (
    tester,
  ) async {
    final repository = _FakeLeaveRepository();
    await tester.pumpWidget(_app(const ApplyLeaveScreen(), repository));
    await tester.pumpAndSettle();
    await _pickSingleLeaveDay(tester);
    expect(find.byKey(const ValueKey('leave-session-choice')), findsOneWidget);
    await tester.tap(find.text('First half'));
    await tester.pumpAndSettle();
    expect(find.text('0.5 day selected'), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('leave-reason-field')),
      'Visit',
    );
    await tester.tap(find.byKey(const ValueKey('submit-leave-button')));
    await tester.pumpAndSettle();
    expect(repository.lastAppliedType, 'sick');
    expect(repository.lastSession, 'first_half');
  });

  testWidgets(
    'employee leave tab switches sections and hides Apply on Holidays',
    (tester) async {
      final repository = _FakeLeaveRepository();
      await tester.pumpWidget(_app(const MyLeaveRequestsScreen(), repository));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('apply-leave-button')), findsOneWidget);
      await tester.tap(find.text('Holidays'));
      await tester.pumpAndSettle();
      expect(find.text('Founders day'), findsOneWidget);
      expect(find.byKey(const ValueKey('apply-leave-button')), findsNothing);
      await tester.tap(find.text('Requests'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('apply-leave-button')), findsOneWidget);
    },
  );

  testWidgets('employee leave list shows data, filters and refreshes', (
    tester,
  ) async {
    final repository = _FakeLeaveRepository([_request()]);
    await tester.pumpWidget(_app(const MyLeaveRequestsScreen(), repository));
    await tester.pumpAndSettle();
    expect(find.text('12 - 13 Oct 2026'), findsOneWidget);
    expect(find.text('2 days'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('my-leave-status-filter')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Approved').last);
    await tester.pumpAndSettle();
    expect(find.text('No leave requests yet.'), findsOneWidget);
    expect(repository.mineCalls, 2);
  });

  testWidgets('employee leave list shows empty and server error states', (
    tester,
  ) async {
    final empty = _FakeLeaveRepository();
    await tester.pumpWidget(_app(const MyLeaveRequestsScreen(), empty));
    await tester.pumpAndSettle();
    expect(find.text('No leave requests yet.'), findsOneWidget);
    final failed = _FakeLeaveRepository()
      ..mineError = const AppException(
        code: 'FAIL',
        message: 'Leave service unavailable',
        details: {},
      );
    await tester.pumpWidget(_app(const MyLeaveRequestsScreen(), failed));
    await tester.pumpAndSettle();
    expect(find.text('Leave service unavailable'), findsOneWidget);
  });

  testWidgets(
    'employee list shows loading while the server request is pending',
    (tester) async {
      final repository = _FakeLeaveRepository()
        ..mineCompleter = Completer<List<LeaveRequest>>();
      await tester.pumpWidget(_app(const MyLeaveRequestsScreen(), repository));
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      repository.mineCompleter!.complete([]);
      await tester.pumpAndSettle();
      expect(find.text('No leave requests yet.'), findsOneWidget);
    },
  );

  testWidgets(
    'employee can confirm cancel and sees friendly NOT_PENDING error',
    (tester) async {
      final repository = _FakeLeaveRepository([_request()])
        ..cancelError = const AppException(
          code: 'NOT_PENDING',
          message: 'Conflict',
          details: {},
          statusCode: 409,
        );
      await tester.pumpWidget(_app(const MyLeaveRequestsScreen(), repository));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.text('Cancel leave request?'), findsOneWidget);
      await tester.tap(find.text('Cancel request'));
      await tester.pumpAndSettle();
      expect(
        find.text(
          'This request has already been decided and cannot be cancelled.',
        ),
        findsOneWidget,
      );
      expect(repository.cancelCalls, 1);
      expect(repository.mineCalls, 2);
    },
  );

  testWidgets(
    'employee cancel maps missing requests and refreshes from server',
    (tester) async {
      final repository = _FakeLeaveRepository([_request()])
        ..cancelError = const AppException(
          code: 'LEAVE_NOT_FOUND',
          message: 'Not found',
          details: {},
          statusCode: 404,
        );
      await tester.pumpWidget(_app(const MyLeaveRequestsScreen(), repository));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel request'));
      await tester.pumpAndSettle();
      expect(
        find.text('This leave request could not be found.'),
        findsOneWidget,
      );
      expect(repository.mineCalls, 2);
    },
  );

  testWidgets(
    'apply picker loads server today before presenting the date picker',
    (tester) async {
      final repository = _FakeLeaveRepository();
      await tester.pumpWidget(_app(const ApplyLeaveScreen(), repository));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('leave-date-range-button')));
      await tester.pumpAndSettle();
      expect(find.text('Choose leave dates'), findsOneWidget);
      expect(find.text('October 2026'), findsOneWidget);
      expect(leavePickerWindow('2026-10-12').start, DateTime(2026, 10, 12));
    },
  );

  testWidgets('apply maps leave overlap to a friendly server message', (
    tester,
  ) async {
    final repository = _FakeLeaveRepository()
      ..applyError = const AppException(
        code: 'LEAVE_OVERLAP',
        message: 'Conflict',
        details: {},
        statusCode: 409,
      );
    await tester.pumpWidget(_routerApp(repository));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('apply-leave-button')));
    await tester.pumpAndSettle();
    await _pickTwoLeaveDays(tester);
    await tester.enterText(
      find.byKey(const ValueKey('leave-reason-field')),
      'Family event',
    );
    await tester.tap(find.byKey(const ValueKey('submit-leave-button')));
    await tester.pumpAndSettle();
    expect(
      find.text(
        'You already have a leave request covering some of these dates.',
      ),
      findsOneWidget,
    );
    expect(repository.applyCalls, 1);
  });

  testWidgets('apply form rejects an empty reason before calling the server', (
    tester,
  ) async {
    final repository = _FakeLeaveRepository();
    await tester.pumpWidget(_routerApp(repository));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('apply-leave-button')));
    await tester.pumpAndSettle();
    await _pickTwoLeaveDays(tester);
    await tester.tap(find.byKey(const ValueKey('submit-leave-button')));
    await tester.pumpAndSettle();
    expect(find.text('Enter a reason for your leave request.'), findsOneWidget);
    expect(repository.applyCalls, 0);
  });

  testWidgets(
    'successful apply returns to the list and refreshes from the server',
    (tester) async {
      final repository = _FakeLeaveRepository();
      await tester.pumpWidget(_routerApp(repository));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('apply-leave-button')));
      await tester.pumpAndSettle();
      await _pickTwoLeaveDays(tester);
      await tester.enterText(
        find.byKey(const ValueKey('leave-reason-field')),
        'New request',
      );
      await tester.tap(find.byKey(const ValueKey('submit-leave-button')));
      await tester.pumpAndSettle();
      expect(find.text('New request'), findsOneWidget);
      expect(repository.applyCalls, 1);
      expect(repository.mineCalls, 2);
    },
  );

  testWidgets(
    'admin approves typed requests without a paid or unpaid chooser',
    (tester) async {
      final repository = _FakeLeaveRepository([_request()])
        ..decisionResult = _request(
          status: LeaveStatus.approved,
          noDaysWritten: true,
          skipped: const [
            SkippedDate(date: '2026-10-12', reason: 'weekly_off'),
          ],
        );
      await tester.pumpWidget(
        _app(const AdminLeaveRequestsScreen(), repository),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Asha'));
      await tester.pumpAndSettle();
      expect(find.text('Paid: no salary deduction'), findsNothing);
      expect(find.text('Approval type'), findsNothing);
      expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, 'Approve'))
            .onPressed,
        isNotNull,
      );
      await tester.tap(find.text('Approve'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Confirm'));
      await tester.pump(const Duration(milliseconds: 400));
      expect(
        find.text('No days were written. Every date in the range was skipped.'),
        findsOneWidget,
      );
      expect(find.text('2026-10-12: Sunday / weekly off'), findsOneWidget);
      expect(repository.decideCalls, 1);
    },
  );

  testWidgets(
    'admin list searches employee name and code and handles empty/error states',
    (tester) async {
      final repository = _FakeLeaveRepository([
        _request(),
        _request(id: 'leave-2', name: 'Ravi'),
      ]);
      await tester.pumpWidget(
        _app(const AdminLeaveRequestsScreen(), repository),
      );
      await tester.pumpAndSettle();
      expect(find.text('Asha'), findsOneWidget);
      expect(find.text('Ravi'), findsOneWidget);
      await tester.enterText(
        find.byKey(const ValueKey('admin-leave-search')),
        'EMP002',
      );
      await tester.pumpAndSettle();
      expect(find.text('Ravi'), findsOneWidget);
      expect(find.text('Asha'), findsNothing);

      final empty = _FakeLeaveRepository();
      await tester.pumpWidget(_app(const AdminLeaveRequestsScreen(), empty));
      await tester.pumpAndSettle();
      expect(find.text('No matching leave requests.'), findsOneWidget);
      final failed = _FakeLeaveRepository()
        ..adminError = const AppException(
          code: 'FAIL',
          message: 'Admin queue unavailable',
          details: {},
        );
      await tester.pumpWidget(_app(const AdminLeaveRequestsScreen(), failed));
      await tester.pumpAndSettle();
      expect(find.text('Admin queue unavailable'), findsOneWidget);
    },
  );

  testWidgets('admin list shows loading while its server request is pending', (
    tester,
  ) async {
    final repository = _FakeLeaveRepository()
      ..adminCompleter = Completer<List<LeaveRequest>>();
    await tester.pumpWidget(_app(const AdminLeaveRequestsScreen(), repository));
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    repository.adminCompleter!.complete([]);
    await tester.pumpAndSettle();
    expect(find.text('No matching leave requests.'), findsOneWidget);
  });

  testWidgets(
    'decided requests open read-only details with written and skipped dates',
    (tester) async {
      final repository = _FakeLeaveRepository([
        _request(
          status: LeaveStatus.approved,
          paid: false,
          leaveTypeName: 'Unpaid Leave',
          note: 'Approved',
          written: const ['2026-10-12'],
          skipped: const [SkippedDate(date: '2026-10-13', reason: 'holiday')],
        ),
      ]);
      await tester.pumpWidget(
        _app(const AdminLeaveRequestsScreen(), repository),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('admin-leave-status-filter')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Approved').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Asha'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Unpaid Leave'), findsNWidgets(2));
      expect(find.text('Admin note: Approved'), findsOneWidget);
      expect(find.textContaining('2026-10-12'), findsOneWidget);
      expect(find.text('2026-10-13: Holiday'), findsOneWidget);
      expect(find.text('Reject'), findsNothing);
    },
  );

  testWidgets('reject does not require a leave type and maps ALREADY_DECIDED', (
    tester,
  ) async {
    final repository = _FakeLeaveRepository([_request()])
      ..decisionError = const AppException(
        code: 'ALREADY_DECIDED',
        message: 'Conflict',
        details: {},
        statusCode: 409,
      );
    await tester.pumpWidget(_app(const AdminLeaveRequestsScreen(), repository));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Asha'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<OutlinedButton>(find.widgetWithText(OutlinedButton, 'Reject'))
          .onPressed,
      isNotNull,
    );
    await tester.enterText(
      find.byType(TextField).last,
      'Insufficient coverage',
    );
    await tester.tap(find.text('Reject'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Confirm'));
    await tester.pumpAndSettle();
    expect(find.text('Someone already decided this request.'), findsOneWidget);
    expect(repository.decideCalls, 1);
    expect(repository.lastNote, 'Insufficient coverage');
  });

  testWidgets('old pending request cannot be approved but can be rejected', (
    tester,
  ) async {
    final repository = _FakeLeaveRepository([
      _request(leaveTypeId: null, leaveTypeName: null, paid: null),
    ]);
    await tester.pumpWidget(_app(const AdminLeaveRequestsScreen(), repository));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Asha'));
    await tester.pumpAndSettle();
    expect(
      find.text(
        'This request was made before leave types existed. Reject it, or ask the employee to apply again.',
      ),
      findsOneWidget,
    );
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Approve'))
          .onPressed,
      isNull,
    );
    expect(
      tester
          .widget<OutlinedButton>(find.widgetWithText(OutlinedButton, 'Reject'))
          .onPressed,
      isNotNull,
    );
  });

  testWidgets('pending leave badge displays server request count', (
    tester,
  ) async {
    final repository = _FakeLeaveRepository([
      _request(),
      _request(id: 'leave-2'),
    ]);
    await tester.pumpWidget(_app(const PendingLeaveBadge(), repository));
    await tester.pumpAndSettle();
    expect(find.text('2'), findsOneWidget);
    expect(repository.adminCalls, 1);
  });

  testWidgets('employee detail loads admin leave blocks and branch holidays', (
    tester,
  ) async {
    final leave = _FakeLeaveRepository([_request(id: 'private-id')]);
    final holidays = _EmployeeHolidayRepository();
    await tester.pumpWidget(
      _employeeDetailApp(
        leave,
        employee: _detailEmployee,
        holidayRepository: holidays,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Leave'), findsOneWidget);
    await tester.tap(find.text('Leave'));
    await tester.pumpAndSettle();
    expect(find.text('Remaining leave days'), findsNothing);
    expect(leave.lastBalanceEmpId, 'emp-1');
    expect(leave.lastEmpId, 'emp-1');
    expect(find.textContaining('6.5 days'), findsOneWidget);
    expect(find.textContaining('No limit'), findsWidgets);
    expect(find.text('Showing the latest 200 requests'), findsNothing);
    expect(find.text('private-id'), findsNothing);
    expect(holidays.requestedYear, '2026');
    expect(holidays.requestedBranchId, 'branch-1');
    await tester.drag(
      find.byKey(const ValueKey('employee-leave-scroll')),
      const Offset(0, -900),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('Founders Day'), findsOneWidget);
  });

  testWidgets('pending decision refreshes history and balance', (tester) async {
    final leave = _FakeLeaveRepository([_request()]);
    await tester.pumpWidget(
      _employeeDetailApp(
        leave,
        employee: _detailEmployee,
        holidayRepository: _EmployeeHolidayRepository(),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Leave'));
    await tester.pumpAndSettle();
    expect(leave.lastStatus, 'all');
    final balancesBefore = leave.balanceCalls;
    await tester.drag(
      find.byKey(const ValueKey('employee-leave-scroll')),
      const Offset(0, -1000),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Family event').first);
    await tester.tap(find.text('Family event').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Approve'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Confirm'));
    await tester.pump(const Duration(seconds: 2));
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(leave.decideCalls, 1);
    expect(leave.adminCalls, greaterThan(1));
    expect(leave.balanceCalls, greaterThan(balancesBefore));
  });

  testWidgets('history shows the latest 200 request note at the server cap', (
    tester,
  ) async {
    final requests = List.generate(
      200,
      (index) => _request(id: 'leave-$index'),
    );
    final repository = _FakeLeaveRepository(requests);
    const unassigned = Employee(
      uid: 'emp-cap',
      empCode: 'EMP200',
      name: 'Cap User',
      email: 'cap@example.com',
      role: 'employee',
      status: EmployeeStatus.active,
      doj: '2024-01-01',
      createdAt: '2024-01-01T00:00:00.000Z',
      updatedAt: '2024-01-01T00:00:00.000Z',
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          leaveRepositoryProvider.overrideWithValue(repository),
          leaveBalanceProvider(
            (year: null, empId: unassigned.uid),
          ).overrideWith((ref) => repository.getBalance(empId: unassigned.uid)),
          adminLeaveRequestsProvider((status: 'all', empId: unassigned.uid))
              .overrideWith((ref) async => requests),
          branchesProvider('active')
              .overrideWith((ref) async => const <Branch>[]),
        ],
        child: const MaterialApp(
          home: Scaffold(body: EmployeeLeaveSection(employee: unassigned)),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Showing the latest 200 requests'), findsOneWidget);
  });

  testWidgets(
    'leave history filter and year selector use employee scoped queries',
    (tester) async {
      final leave = _FakeLeaveRepository([_request()]);
      await tester.pumpWidget(
        _employeeDetailApp(
          leave,
          employee: _detailEmployee,
          holidayRepository: _EmployeeHolidayRepository(),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Leave'));
      await tester.pumpAndSettle();
      await tester.drag(
        find.byKey(const ValueKey('employee-leave-scroll')),
        const Offset(0, -500),
      );
      await tester.pumpAndSettle();
      final approvedChip = find.ancestor(
        of: find.text('Approved'),
        matching: find.byType(ChoiceChip),
      );
      await tester.ensureVisible(approvedChip);
      await tester.tap(approvedChip);
      await tester.pumpAndSettle();
      expect(leave.lastStatus, 'approved');
      expect(leave.lastEmpId, 'emp-1');
      await tester.drag(
        find.byKey(const ValueKey('employee-leave-scroll')),
        const Offset(0, -100),
      );
      await tester.pumpAndSettle();
      final pendingChip = find.ancestor(
        of: find.text('Pending'),
        matching: find.byType(ChoiceChip),
      );
      await tester.tap(pendingChip);
      await tester.pumpAndSettle();
      expect(leave.lastStatus, 'pending');
      await tester.drag(
        find.byKey(const ValueKey('employee-leave-scroll')),
        const Offset(0, 500),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Previous leave year'));
      await tester.pumpAndSettle();
      expect(leave.lastBalanceYear, 2025);
    },
  );

  testWidgets(
    'admin role does not show Leave and unassigned branch skips query',
    (tester) async {
      const admin = Employee(
        uid: 'admin-1',
        empCode: 'ADM001',
        name: 'Admin',
        email: 'admin@example.com',
        role: 'admin',
        status: EmployeeStatus.active,
        doj: '2024-01-01',
        createdAt: '2024-01-01T00:00:00.000Z',
        updatedAt: '2024-01-01T00:00:00.000Z',
      );
      final leave = _FakeLeaveRepository();
      await tester.pumpWidget(_employeeDetailApp(leave, employee: admin));
      await tester.pumpAndSettle();
      expect(find.text('Leave'), findsNothing);

      const unassigned = Employee(
        uid: 'emp-2',
        empCode: 'EMP002',
        name: 'Ravi',
        email: 'ravi@example.com',
        role: 'employee',
        status: EmployeeStatus.active,
        doj: '2024-01-01',
        createdAt: '2024-01-01T00:00:00.000Z',
        updatedAt: '2024-01-01T00:00:00.000Z',
      );
      final holidays = _EmployeeHolidayRepository();
      await tester.pumpWidget(
        _employeeDetailApp(
          leave,
          employee: unassigned,
          holidayRepository: holidays,
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Leave'));
      await tester.pumpAndSettle();
      await tester.drag(
        find.byKey(const ValueKey('employee-leave-scroll')),
        const Offset(0, -1000),
      );
      await tester.pumpAndSettle();
      expect(
        find.text(
          'No primary branch is assigned, so only company-wide holidays apply. See the Holidays screen.',
        ),
        findsOneWidget,
      );
      expect(holidays.requestedBranchId, isNull);
    },
  );

  testWidgets('one leave block failure does not hide the other blocks', (
    tester,
  ) async {
    final leave = _FakeLeaveRepository([_request()])
      ..balanceError = const AppException(
        code: 'BALANCE_FAILURE',
        message: 'Balance unavailable',
        details: {},
      );
    await tester.pumpWidget(
      _employeeDetailApp(
        leave,
        employee: _detailEmployee,
        holidayRepository: _EmployeeHolidayRepository(),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Leave'));
    await tester.pumpAndSettle();
    expect(find.text('Could not load leave balances.'), findsOneWidget);
    expect(find.textContaining('Family event'), findsOneWidget);
    await tester.drag(
      find.byKey(const ValueKey('employee-leave-scroll')),
      const Offset(0, -1500),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('Founders Day'), findsOneWidget);
  });

  testWidgets('decided history opens read-only details without employee IDs', (
    tester,
  ) async {
    final decided = _request(
      status: LeaveStatus.approved,
      note: 'Approved by manager',
      written: const ['2026-10-12'],
      skipped: const [SkippedDate(date: '2026-10-13', reason: 'weekly_off')],
    );
    final leave = _FakeLeaveRepository([decided]);
    await tester.pumpWidget(
      _employeeDetailApp(
        leave,
        employee: _detailEmployee,
        holidayRepository: _EmployeeHolidayRepository(),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Leave'));
    await tester.pumpAndSettle();
    await tester.drag(
      find.byKey(const ValueKey('employee-leave-scroll')),
      const Offset(0, -400),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('Family event').first);
    await tester.pumpAndSettle();
    expect(find.text('Admin note: Approved by manager'), findsWidgets);
    expect(find.text('2026-10-12'), findsWidgets);
    expect(find.text('emp-1'), findsNothing);
    expect(find.text('Approve'), findsNothing);
  });

  testWidgets('calendar button navigates to this employee calendar route', (
    tester,
  ) async {
    final repository = _FakeLeaveRepository();
    final router = GoRouter(
      initialLocation: '/leave',
      routes: [
        GoRoute(
          path: '/leave',
          builder: (_, _) =>
              Scaffold(body: EmployeeLeaveSection(employee: _detailEmployee)),
        ),
        GoRoute(
          path: '/admin/attendance/employee/:id',
          builder: (_, state) =>
              Scaffold(body: Text('Calendar ${state.pathParameters['id']}')),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          leaveRepositoryProvider.overrideWithValue(repository),
          branchesProvider('active')
              .overrideWith((ref) async => const <Branch>[]),
          adminAttendanceHolidaysProvider((year: '2026', branchId: 'branch-1'))
              .overrideWith((ref) async => const <AttendanceHoliday>[]),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
    await tester.drag(
      find.byKey(const ValueKey('employee-leave-scroll')),
      const Offset(0, -1500),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('View attendance calendar'));
    await tester.tap(find.text('View attendance calendar'));
    await tester.pumpAndSettle();
    expect(find.text('Calendar emp-1'), findsOneWidget);
  });
}
