import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class AdminShellScreen extends StatelessWidget {
  const AdminShellScreen({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final path = GoRouterState.of(context).uri.path;
    final selectedIndex = path.startsWith('/admin/branches')
        ? 2
        : path.startsWith('/admin/employees')
        ? 1
        : 0;
    return Scaffold(
      body: child,
      bottomNavigationBar: NavigationBar(
        selectedIndex: selectedIndex,
        onDestinationSelected: (index) {
          context.go(switch (index) {
            0 => '/admin/dashboard',
            1 => '/admin/employees',
            _ => '/admin/branches',
          });
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.dashboard_outlined),
            selectedIcon: Icon(Icons.dashboard),
            label: 'Dashboard',
          ),
          NavigationDestination(
            icon: Icon(Icons.people_outline),
            selectedIcon: Icon(Icons.people),
            label: 'Employees',
          ),
          NavigationDestination(
            icon: Icon(Icons.location_on_outlined),
            selectedIcon: Icon(Icons.location_on),
            label: 'Branches',
          ),
        ],
      ),
    );
  }
}
