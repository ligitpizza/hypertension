import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/theme_mode.dart';
import '../../../shared/widgets/confirm_sign_out.dart';
import '../../auth/state/auth_providers.dart';

/// Bottom navigation for the patient app (Fig 4.3.2.1): Home, Vitals, Meds, Records, More.
class PatientShell extends StatelessWidget {
  const PatientShell({super.key, required this.location, required this.child});

  final String location;
  final Widget child;

  static const tabs = [
    ('/dashboard', 'Home', Icons.home_outlined, Icons.home),
    ('/vitals', 'Vitals', Icons.show_chart, Icons.show_chart),
    ('/medications', 'Meds', Icons.medication_outlined, Icons.medication),
    ('/records', 'Records', Icons.folder_shared_outlined, Icons.folder_shared),
    ('/more', 'More', Icons.more_horiz, Icons.more_horiz),
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
        body: child,
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

/// "More" tab: account actions until Settings (Module 12) replaces it.
class MorePage extends ConsumerWidget {
  const MorePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider).value;
    return Scaffold(
      appBar: AppBar(title: const Text('More')),
      body: ListView(
        children: [
          if (user != null)
            ListTile(
              leading: const CircleAvatar(child: Icon(Icons.person)),
              title: Text(user.name),
              subtitle: Text(user.email),
            ),
          if (user?.linkCode != null)
            ListTile(
              key: const Key('more-link-code'),
              leading: const Icon(Icons.family_restroom),
              title: const Text('Family link code'),
              subtitle: Text(
                'Share ${user!.linkCode} with a family member to let them follow '
                'your readings.',
              ),
            ),
          const ListTile(
            leading: Icon(Icons.palette_outlined),
            title: Text('Theme'),
            subtitle: Padding(padding: EdgeInsets.only(top: 8), child: ThemeModeSelector()),
          ),
          const ListTile(
            leading: Icon(Icons.event_outlined),
            title: Text('Appointments'),
            subtitle: Text('Coming soon'),
          ),
          const ListTile(
            leading: Icon(Icons.settings_outlined),
            title: Text('Settings'),
            subtitle: Text('Coming soon'),
          ),
          const Divider(),
          ListTile(
            key: const Key('more-sign-out'),
            leading: const Icon(Icons.logout),
            title: const Text('Sign out'),
            onTap: () => confirmAndSignOut(context, ref),
          ),
        ],
      ),
    );
  }
}
