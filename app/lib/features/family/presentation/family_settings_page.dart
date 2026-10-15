import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/theme_mode.dart';
import '../../../shared/widgets/confirm_sign_out.dart';
import '../../auth/state/auth_providers.dart';
import '../state/family_providers.dart';

/// Family app settings: account, who you follow, theme, sign out.
class FamilySettingsPage extends ConsumerWidget {
  const FamilySettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider).value;
    final linked = ref.watch(linkedPatientIdProvider).value;
    final person = linked == null ? null : ref.watch(linkedPersonProvider(linked)).value;
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: ListTile(
              leading: const Icon(Icons.person_outline),
              title: Text(user?.name ?? ''),
              subtitle: Text(user?.email ?? ''),
            ),
          ),
          Card(
            child: ListTile(
              key: const Key('family-settings-linked'),
              leading: const Icon(Icons.family_restroom),
              title: Text(
                linked == null ? 'Not following anyone' : 'Following ${person?.name ?? '…'}',
              ),
              subtitle: const Text('Manage under Patients'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.go('/family/link'),
            ),
          ),
          const Card(
            child: ListTile(
              leading: Icon(Icons.notifications_active_outlined),
              title: Text('Emergency alerts are always delivered.'),
              subtitle: Text('Allow notifications for CareFlow Family so you never miss one.'),
            ),
          ),
          const Card(
            child: ListTile(
              leading: Icon(Icons.palette_outlined),
              title: Text('Theme'),
              subtitle: Padding(padding: EdgeInsets.only(top: 8), child: ThemeModeSelector()),
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.tonalIcon(
            key: const Key('family-sign-out'),
            onPressed: () => confirmAndSignOut(context, ref),
            icon: const Icon(Icons.logout),
            label: const Text('Sign out'),
          ),
        ],
      ),
    );
  }
}
