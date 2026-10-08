import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/auth_providers.dart';
import '../domain/user_profile.dart';
import '../../attendance/presentation/employee_attendance_screen.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({required this.role, super.key});

  final UserRole role;

  Future<void> _signOut(BuildContext context, WidgetRef ref) async {
    try {
      await ref.read(authControllerProvider).signOut();
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not sign out. Please try again.')),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(currentProfileProvider).asData?.value;
    final isAdmin = role == UserRole.admin;
    if (!isAdmin) return const EmployeeAttendanceScreen();

    return Scaffold(
      appBar: AppBar(
        title: Text(isAdmin ? 'Admin home' : 'Employee home'),
        backgroundColor: isAdmin
            ? Theme.of(context).colorScheme.primaryContainer
            : Theme.of(context).colorScheme.tertiaryContainer,
        actions: [
          IconButton(
            tooltip: 'Log out',
            onPressed: () => _signOut(context, ref),
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: profile == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          isAdmin ? 'Administrator' : 'Employee',
                          style: Theme.of(context).textTheme.headlineSmall,
                        ),
                        const SizedBox(height: 16),
                        Text('Name: ${profile.name}'),
                        Text('Role: ${profile.role.name}'),
                        Text('Email: ${profile.email}'),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                _DashboardTile(
                  title: 'Attendance',
                  icon: Icons.fact_check_outlined,
                  onTap: () => context.go('/admin/attendance'),
                ),
                _DashboardTile(
                  title: 'Holidays',
                  icon: Icons.celebration_outlined,
                  onTap: () => context.go('/admin/holidays'),
                ),
                _DashboardTile(
                  title: 'Settings',
                  icon: Icons.settings_outlined,
                  onTap: () => context.go('/admin/settings'),
                ),
                _DashboardTile(
                  title: 'Flagged check-ins',
                  icon: Icons.location_off_outlined,
                  onTap: () => context.go('/admin/flagged-checkins'),
                ),
              ],
            ),
    );
  }
}

class _DashboardTile extends StatelessWidget {
  const _DashboardTile({
    required this.title,
    required this.icon,
    required this.onTap,
  });

  final String title;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Card(
    child: ListTile(
      leading: Icon(icon),
      title: Text(title),
      trailing: const Icon(Icons.chevron_right),
      onTap: onTap,
    ),
  );
}
