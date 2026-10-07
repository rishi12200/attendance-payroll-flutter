import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/presentation/home_screen.dart';
import '../../features/auth/presentation/login_screen.dart';
import '../../features/auth/domain/user_profile.dart';
import '../../features/employees/presentation/admin_shell.dart';
import '../../features/employees/presentation/add_employee_screen.dart';
import '../../features/employees/presentation/employee_detail_screen.dart';
import '../../features/employees/presentation/employee_edit_screen.dart';
import '../../features/employees/presentation/employee_list_screen.dart';
import '../auth/auth_providers.dart';
import 'router_redirect.dart';

class _RouterRefresh extends ChangeNotifier {
  void refresh() => notifyListeners();
}

final routerProvider = Provider<GoRouter>((ref) {
  final refresh = _RouterRefresh();
  ref.listen(authStateProvider, (_, _) => refresh.refresh());
  ref.listen(currentProfileProvider, (_, _) => refresh.refresh());
  ref.onDispose(refresh.dispose);

  return GoRouter(
    initialLocation: '/',
    refreshListenable: refresh,
    redirect: (context, state) {
      final authState = ref.read(authStateProvider);
      final profileState = ref.read(currentProfileProvider);
      return routerRedirect(
        location: state.matchedLocation,
        authLoading: authState.isLoading,
        isSignedIn: authState.asData?.value != null,
        profileLoading: profileState.isLoading,
        profileError: profileState.hasError,
        profile: profileState.asData?.value,
      );
    },
    routes: [
      GoRoute(
        path: '/',
        builder: (context, state) =>
            const Scaffold(body: Center(child: CircularProgressIndicator())),
      ),
      GoRoute(
        path: '/login',
        builder: (context, state) => const LoginScreen(),
      ),
      GoRoute(
        path: '/admin',
        redirect: (context, state) => '/admin/dashboard',
      ),
      ShellRoute(
        builder: (context, state, child) => AdminShellScreen(child: child),
        routes: [
          GoRoute(
            path: '/admin/dashboard',
            builder: (context, state) =>
                const HomeScreen(role: UserRole.admin),
          ),
          GoRoute(
            path: '/admin/employees',
            builder: (context, state) => const EmployeeListScreen(),
            routes: [
              GoRoute(
                path: 'new',
                builder: (context, state) => const AddEmployeeScreen(),
              ),
              GoRoute(
                path: ':id',
                builder: (context, state) =>
                    EmployeeDetailScreen(id: state.pathParameters['id']!),
                routes: [
                  GoRoute(
                    path: 'edit',
                    builder: (context, state) => EmployeeEditScreen(
                      id: state.pathParameters['id']!,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
      GoRoute(
        path: '/employee',
        builder: (context, state) =>
            const HomeScreen(role: UserRole.employee),
        routes: [
          GoRoute(
            path: ':section',
            builder: (context, state) =>
                const HomeScreen(role: UserRole.employee),
          ),
        ],
      ),
    ],
  );
});
