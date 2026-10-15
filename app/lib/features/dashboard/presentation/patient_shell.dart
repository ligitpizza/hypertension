import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../family/presentation/emergency_location_updater.dart';

/// Bottom navigation for the patient app: Home, Vitals, Meds, Records, Settings
/// (Fig 4.3.11.1; Fig 4.3.2.1 showed "More" before Settings existed).
class PatientShell extends StatelessWidget {
  const PatientShell({super.key, required this.location, required this.child});

  final String location;
  final Widget child;

  static const tabs = [
    ('/dashboard', 'Home', Icons.home_outlined, Icons.home),
    ('/vitals', 'Vitals', Icons.show_chart, Icons.show_chart),
    ('/medications', 'Meds', Icons.medication_outlined, Icons.medication),
    ('/records', 'Records', Icons.folder_shared_outlined, Icons.folder_shared),
    ('/settings', 'Settings', Icons.settings_outlined, Icons.settings),
  ];

  @override
  Widget build(BuildContext context) {
    final index = tabs.indexWhere((t) => location.startsWith(t.$1));
    final onHome = index <= 0;
    // Android back on another tab returns to Home; back on Home leaves the app.
    return PopScope(
      canPop: onHome,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) context.go(tabs.first.$1);
      },
      child: Scaffold(
        // D-62: keeps an open emergency alert's location fresh while the app is on screen.
        body: EmergencyLocationUpdater(child: child),
        bottomNavigationBar: NavigationBar(
          selectedIndex: index < 0 ? 0 : index,
          onDestinationSelected: (i) => context.go(tabs[i].$1),
          destinations: [
            for (final (_, label, icon, selected) in tabs)
              NavigationDestination(icon: Icon(icon), selectedIcon: Icon(selected), label: label),
          ],
        ),
      ),
    );
  }
}

/// Placeholder for patient features built in later modules.
class ComingSoonPage extends StatelessWidget {
  const ComingSoonPage({super.key, required this.title, required this.note});

  final String title;
  final String note;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(title)),
    body: Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(note, textAlign: TextAlign.center),
      ),
    ),
  );
}
