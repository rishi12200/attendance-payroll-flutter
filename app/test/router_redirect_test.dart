import 'package:app/core/router/router_redirect.dart';
import 'package:app/core/router/app_router.dart';
import 'package:app/core/auth/auth_providers.dart';
import 'package:app/features/auth/domain/auth_repository.dart';
import 'package:app/features/auth/domain/user_profile.dart';
import 'package:app/features/branches/data/branches_providers.dart';
import 'package:app/features/branches/domain/branch.dart';
import 'package:app/features/branches/presentation/branch_list_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _RouterApp extends ConsumerWidget {
  const _RouterApp();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp.router(routerConfig: ref.watch(routerProvider));
  }
}

UserProfile profile(UserRole role) => UserProfile(
  uid: 'uid-1',
  name: 'Test User',
  email: 'test@example.com',
  role: role,
);

void main() {
  test('holds the splash location while authentication or profile loads', () {
    expect(
      routerRedirect(
        location: '/admin/dashboard',
        authLoading: true,
        isSignedIn: false,
        profileLoading: false,
        profileError: false,
        profile: null,
      ),
      '/',
    );
    expect(
      routerRedirect(
        location: '/login',
        authLoading: false,
        isSignedIn: true,
        profileLoading: true,
        profileError: false,
        profile: null,
      ),
      '/',
    );
  });

  test('redirects signed-out users to login', () {
    expect(
      routerRedirect(
        location: '/admin',
        authLoading: false,
        isSignedIn: false,
        profileLoading: false,
        profileError: false,
        profile: null,
      ),
      '/login',
    );
  });

  test('routes to the server-provided role and blocks other role paths', () {
    final admin = profile(UserRole.admin);
    final employee = profile(UserRole.employee);

    expect(
      routerRedirect(
        location: '/',
        authLoading: false,
        isSignedIn: true,
        profileLoading: false,
        profileError: false,
        profile: admin,
      ),
      '/admin/dashboard',
    );
    expect(
      routerRedirect(
        location: '/employee',
        authLoading: false,
        isSignedIn: true,
        profileLoading: false,
        profileError: false,
        profile: admin,
      ),
      '/admin/dashboard',
    );
    expect(
      routerRedirect(
        location: '/admin/employees',
        authLoading: false,
        isSignedIn: true,
        profileLoading: false,
        profileError: false,
        profile: employee,
      ),
      '/employee',
    );
    expect(
      routerRedirect(
        location: '/admin/employees/employee-1/edit',
        authLoading: false,
        isSignedIn: true,
        profileLoading: false,
        profileError: false,
        profile: employee,
      ),
      '/employee',
    );
    expect(
      routerRedirect(
        location: '/admin/branches',
        authLoading: false,
        isSignedIn: true,
        profileLoading: false,
        profileError: false,
        profile: employee,
      ),
      '/employee',
    );
    expect(
      routerRedirect(
        location: '/admin/branches/branch-1',
        authLoading: false,
        isSignedIn: true,
        profileLoading: false,
        profileError: false,
        profile: employee,
      ),
      '/employee',
    );
    expect(
      routerRedirect(
        location: '/administrator',
        authLoading: false,
        isSignedIn: true,
        profileLoading: false,
        profileError: false,
        profile: employee,
      ),
      '/employee',
    );
    expect(
      routerRedirect(
        location: '/employee',
        authLoading: false,
        isSignedIn: true,
        profileLoading: false,
        profileError: false,
        profile: employee,
      ),
      isNull,
    );
  });

  testWidgets('admin Branches tab opens the registered branch screen', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authStateProvider.overrideWith(
            (ref) => Stream.value(
              const AuthIdentity(uid: 'admin-1', email: 'admin@example.com'),
            ),
          ),
          currentProfileProvider.overrideWith(
            (ref) async => profile(UserRole.admin),
          ),
          branchesProvider('active').overrideWith((ref) async => <Branch>[]),
        ],
        child: const _RouterApp(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Branches'));
    await tester.pumpAndSettle();

    expect(find.byType(BranchListScreen), findsOneWidget);
    expect(find.text('No branches found.'), findsOneWidget);
  });
}
