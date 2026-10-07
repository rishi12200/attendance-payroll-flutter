import '../../features/auth/domain/user_profile.dart';

String? routerRedirect({
  required String location,
  required bool authLoading,
  required bool isSignedIn,
  required bool profileLoading,
  required bool profileError,
  required UserProfile? profile,
}) {
  if (authLoading || (isSignedIn && profileLoading)) {
    return location == '/' ? null : '/';
  }

  if (!isSignedIn) {
    return location == '/login' ? null : '/login';
  }

  if (profileError || profile == null) {
    return location == '/login' ? null : '/login';
  }

  final home = profile.role == UserRole.admin
      ? '/admin/dashboard'
      : '/employee';
  if (location == '/' || location == '/login') return home;

  final canAccessRoleRoutes = switch (profile.role) {
    UserRole.admin =>
      location == '/admin' || location.startsWith('/admin/'),
    UserRole.employee =>
      location == '/employee' || location.startsWith('/employee/'),
  };
  return canAccessRoleRoutes ? null : home;
}
