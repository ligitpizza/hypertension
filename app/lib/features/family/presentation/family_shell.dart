import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../auth/presentation/family_theme.dart';

/// Family app bottom navigation (Figs 4.3.16.1-4.3.16.3): Dashboard, Patients, Settings.
class FamilyShell extends StatelessWidget {
  const FamilyShell({super.key, required this.location, required this.child});

  final String location;
  final Widget child;

  static const _tabs = ['/family/home', '/family/link', '/family/settings'];

  @override
  Widget build(BuildContext context) {
    final index = _tabs.indexWhere(location.startsWith);
    // D-63: the family side keeps the teal family colours inside the CareFlow app.
    return Theme(
      data: familyTheme(Theme.of(context)),
      child: Scaffold(
        body: child,
        bottomNavigationBar: NavigationBar(
          selectedIndex: index < 0 ? 0 : index,
          onDestinationSelected: (i) => context.go(_tabs[i]),
          destinations: const [
            NavigationDestination(icon: Icon(Icons.dashboard_outlined), label: 'Dashboard'),
            NavigationDestination(icon: Icon(Icons.group_outlined), label: 'Patients'),
            NavigationDestination(icon: Icon(Icons.settings_outlined), label: 'Settings'),
          ],
        ),
      ),
    );
  }
}
