import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
      body: Center(
        child: profile == null
            ? const CircularProgressIndicator()
            : Card(
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
      ),
    );
  }
}
