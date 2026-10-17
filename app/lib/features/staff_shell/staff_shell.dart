import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants/enums.dart';
import '../../core/theme/theme_mode.dart';
import '../auth/presentation/widgets/role_toggle.dart';
import '../../shared/widgets/confirm_sign_out.dart';
import '../auth/state/auth_providers.dart';
import '../../shared/widgets/harvey_logo.dart';
import '../notifications/presentation/notification_bell.dart';

class StaffDestination {
  const StaffDestination(this.path, this.label, this.icon);
  final String path;
  final String label;
  final IconData icon;
}

/// Destinations per staff role (NFR-3.2: role-specific interface). Grows per module.
List<StaffDestination> staffDestinations(UserRole role) => switch (role) {
  UserRole.doctor => const [
    StaffDestination('/doctor/dashboard', 'Dashboard', Icons.dashboard_outlined), // D-77
    StaffDestination('/doctor', 'Patients', Icons.people_outline),
    StaffDestination('/doctor/prescriptions', 'Prescriptions', Icons.medication_outlined), // D-78
    StaffDestination('/doctor/calendar', 'Calendar', Icons.calendar_month_outlined),
    StaffDestination('/doctor/messages', 'Messages', Icons.chat_bubble_outline),
    StaffDestination('/doctor/admin-center', 'Admin center', Icons.support_agent), // D-78
  ],
  UserRole.pharmacist => const [
    StaffDestination('/pharmacy/dashboard', 'Dashboard', Icons.dashboard_outlined), // D-77
    StaffDestination('/pharmacy', 'Orders', Icons.local_pharmacy_outlined),
    // D-70: tracking, inventory and patients apart from the order queue.
    StaffDestination('/pharmacy/tracking', 'Tracking', Icons.local_shipping_outlined),
    StaffDestination('/pharmacy/inventory', 'Inventory', Icons.inventory_2_outlined),
    StaffDestination('/pharmacy/patients', 'Patients', Icons.people_outline),
    StaffDestination('/pharmacy/messages', 'Messages', Icons.chat_bubble_outline), // D-69
    StaffDestination('/pharmacy/admin-center', 'Admin center', Icons.support_agent), // D-78
  ],
  UserRole.admin => const [
    StaffDestination('/admin/dashboard', 'Dashboard', Icons.dashboard_outlined), // D-77
    StaffDestination('/admin/users', 'Users', Icons.manage_accounts_outlined),
    StaffDestination('/admin/calendar', 'Calendar', Icons.calendar_month_outlined),
    StaffDestination('/admin/appointments', 'Appointments', Icons.event_note_outlined),
    StaffDestination('/admin/assignments', 'Assignments', Icons.assignment_ind_outlined),
    StaffDestination('/admin/messages', 'Messages', Icons.chat_bubble_outline), // D-76
    StaffDestination('/admin/requests', 'Staff requests', Icons.support_agent), // D-78
    StaffDestination('/admin/audit-logs', 'Audit logs', Icons.policy_outlined),
    StaffDestination('/admin/orders', 'Orders', Icons.receipt_long_outlined), // D-70
    StaffDestination('/admin/deliveries', 'Deliveries', Icons.local_shipping_outlined),
    StaffDestination('/admin/inventory', 'Inventory', Icons.inventory_2_outlined), // D-70
    StaffDestination('/admin/analytics/hospital', 'Hospital analytics', Icons.insights_outlined),
    StaffDestination('/admin/analytics/system', 'Usage analytics', Icons.query_stats),
    StaffDestination('/admin/system-health', 'System health', Icons.health_and_safety_outlined),
  ],
  _ => const [],
};

/// The destination whose path is the longest prefix of [location] ('/doctor/messages/x'
/// selects Messages, not Patients).
int selectedDestination(List<StaffDestination> destinations, String location) {
  var best = -1;
  for (var i = 0; i < destinations.length; i++) {
    final p = destinations[i].path;
    if (location.startsWith(p) && (best < 0 || p.length > destinations[best].path.length)) {
      best = i;
    }
  }
  return best;
}

/// Home route for each staff role (D-77: their dashboard).
String staffHome(UserRole? role) => switch (role) {
  UserRole.pharmacist => '/pharmacy/dashboard',
  UserRole.admin => '/admin/dashboard',
  _ => '/doctor/dashboard',
};

/// D-77: each role's Settings page (bottom of the left nav).
String staffSettingsPath(UserRole? role) => switch (role) {
  UserRole.pharmacist => '/pharmacy/settings',
  UserRole.admin => '/admin/settings',
  _ => '/doctor/settings',
};

/// Sidebar shell for the Staff Web Portal (docs/05: NavigationRail at >= 800 px).
class StaffShell extends ConsumerWidget {
  const StaffShell({super.key, required this.location, required this.child});

  final String location;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider).value;
    final role = user?.role ?? UserRole.doctor;
    final destinations = staffDestinations(role);
    final selected = selectedDestination(destinations, location);
    final wide = MediaQuery.sizeOf(context).width >= 800;

    Future<void> signOut() => confirmAndSignOut(context, ref);

    final settingsPath = staffSettingsPath(role);
    final onSettings = location.startsWith(settingsPath);

    // D-77 top bar: logo, who is signed in, the bell, theme and sign out.
    final light = Theme.of(context).brightness == Brightness.light;

    // D-78: Harvey blue gradient (navy in dark mode), white text and icons.
    final header = AppBar(
      key: const Key('staff-top-bar'),
      foregroundColor: Colors.white,
      iconTheme: const IconThemeData(color: Colors.white),
      actionsIconTheme: const IconThemeData(color: Colors.white),
      flexibleSpace: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: light
                ? const [Color(0xFF0D47A1), Color(0xFF1E88E5)]
                : const [Color(0xFF0A1931), Color(0xFF15305C)],
          ),
        ),
      ),
      title: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8)),
            child: const HarveyLogo.mark(size: 26),
          ),
          const SizedBox(width: 10),
          const Text(
            'Harvey Pro',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
          ),
        ],
      ),
      actions: [
        if (user != null && wide)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Center(
              child: Text(
                '${user.name} · ${RoleToggle.label(user.role)}',
                style: const TextStyle(color: Colors.white),
              ),
            ),
          ),
        const NotificationBell(panel: true, color: Colors.white),
        const ThemeModeMenuButton(),
        if (!wide)
          IconButton(
            key: const Key('staff-settings-narrow'),
            tooltip: 'Settings',
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => context.go(settingsPath),
          ),
        IconButton(
          key: const Key('staff-sign-out'),
          tooltip: 'Sign out',
          icon: const Icon(Icons.logout),
          onPressed: signOut,
        ),
        const SizedBox(width: 4),
      ],
    );

    if (!wide || destinations.length < 2) {
      return Scaffold(appBar: header, body: child);
    }
    return Scaffold(
      appBar: header,
      body: Row(
        children: [
          NavigationRail(
            // D-77: grey in light mode so the menu stands apart from the page.
            backgroundColor: light ? Colors.grey.shade200 : null,
            selectedIndex: onSettings || selected < 0 ? null : selected,
            labelType: NavigationRailLabelType.all,
            destinations: [
              for (final d in destinations)
                NavigationRailDestination(icon: Icon(d.icon), label: Text(d.label)),
            ],
            onDestinationSelected: (i) => context.go(destinations[i].path),
            trailing: Expanded(
              child: Align(
                alignment: Alignment.bottomCenter,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        key: const Key('staff-settings'),
                        tooltip: 'Settings',
                        isSelected: onSettings,
                        icon: const Icon(Icons.settings_outlined),
                        selectedIcon: const Icon(Icons.settings),
                        onPressed: () => context.go(settingsPath),
                      ),
                      Text('Settings', style: Theme.of(context).textTheme.labelMedium),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const VerticalDivider(width: 1),
          Expanded(child: child),
        ],
      ),
    );
  }
}

/// Placeholder body for portal sections built in later increments.
class ComingSoon extends StatelessWidget {
  const ComingSoon({super.key, required this.title, required this.note});

  final String title;
  final String note;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(title, style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 8),
          Text(note, textAlign: TextAlign.center),
        ],
      ),
    ),
  );
}
