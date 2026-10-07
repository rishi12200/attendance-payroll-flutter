import 'package:app/core/router/router_redirect.dart';
import 'package:app/features/auth/domain/user_profile.dart';
import 'package:flutter_test/flutter_test.dart';

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
}
