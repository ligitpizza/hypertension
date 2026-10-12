import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants/enums.dart';
import '../auth/presentation/widgets/role_toggle.dart';
import '../auth/state/auth_providers.dart';

class StaffDestination {
  const StaffDestination(this.path, this.label, this.icon);
  final String path;
  final String label;
  final IconData icon;
}

/// Destinations per staff role (NFR-3.2: role-specific interface). Grows per module.
List<StaffDestination> staffDestinations(UserRole role) => switch (role) {
  UserRole.doctor => const [StaffDestination('/doctor', 'Patients', Icons.people_outline)],
  UserRole.pharmacist => const [
    StaffDestination('/pharmacy', 'Orders', Icons.local_pharmacy_outlined),
  ],
  UserRole.admin => const [
    StaffDestination('/admin/users', 'Users', Icons.manage_accounts_outlined),
  ],
  _ => const [],
};

/// Home route for each staff role.
String staffHome(UserRole? role) => switch (role) {
  UserRole.pharmacist => '/pharmacy',
  UserRole.admin => '/admin/users',
  _ => '/doctor',
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
    final selected = destinations.indexWhere((d) => location.startsWith(d.path));
    final wide = MediaQuery.sizeOf(context).width >= 800;

    Future<void> signOut() => ref.read(authRepositoryProvider).signOut(ClientApp.staff);

    final header = AppBar(
      title: const Text('CareFlow Pro'),
      actions: [
        if (user != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Center(child: Text('${user.name} · ${RoleToggle.label(user.role)}')),
          ),
        IconButton(
          key: const Key('staff-sign-out'),
          tooltip: 'Sign out',
          icon: const Icon(Icons.logout),
          onPressed: signOut,
        ),
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
            selectedIndex: selected < 0 ? 0 : selected,
            labelType: NavigationRailLabelType.all,
            destinations: [
              for (final d in destinations)
                NavigationRailDestination(icon: Icon(d.icon), label: Text(d.label)),
            ],
            onDestinationSelected: (i) => context.go(destinations[i].path),
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
