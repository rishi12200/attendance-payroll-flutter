import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class EmployeeShell extends StatelessWidget {
  const EmployeeShell({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final attendance =
        GoRouterState.of(context).uri.path == '/employee/attendance';
    return Scaffold(
      body: child,
      bottomNavigationBar: NavigationBar(
        selectedIndex: attendance ? 1 : 0,
        onDestinationSelected: (index) =>
            context.go(index == 0 ? '/employee' : '/employee/attendance'),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: 'Home',
          ),
          NavigationDestination(
            icon: Icon(Icons.calendar_month_outlined),
            selectedIcon: Icon(Icons.calendar_month),
            label: 'Attendance',
          ),
        ],
      ),
    );
  }
}
