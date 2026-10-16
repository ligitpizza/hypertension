import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/theme_mode.dart';
import '../../../shared/widgets/confirm_sign_out.dart';
import '../../auth/domain/app_user.dart';
import '../../auth/state/auth_providers.dart';
import '../state/settings_providers.dart';
import 'data_privacy_page.dart';

/// Fig 4.3.11.1 Settings (FR-12.1, FR-12.2; UC12.1-UC12.4; D-45).
class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({super.key});

  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage> {
  /// Shown while a toggle is being saved, so the switch moves at once.
  NotificationPrefs? _pending;

  Future<void> _setPrefs(NotificationPrefs prefs) async {
    setState(() => _pending = prefs);
    try {
      await ref.read(settingsRepositoryProvider).updateNotifications(prefs);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Could not save your notification setting.')));
      }
    } finally {
      if (mounted) setState(() => _pending = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider).value;
    final prefs = _pending ?? user?.notificationPrefs ?? const NotificationPrefs();
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (user != null) _ProfileHeader(user: user),
          const SizedBox(height: 16),
          Text('Account settings', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          Card(
            child: Column(
              children: [
                _NavTile(
                  key: const Key('settings-personal'),
                  icon: Icons.person_outline,
                  title: 'Personal information',
                  subtitle: 'Update your name, date of birth, gender',
                  path: '/settings/personal',
                ),
                _NavTile(
                  key: const Key('settings-contact'),
                  icon: Icons.contact_phone_outlined,
                  title: 'Contact details',
                  subtitle: 'Phone number, emergency contact',
                  path: '/settings/contact',
                ),
                // D-69: used to pre-fill medication deliveries.
                _NavTile(
                  key: const Key('settings-address'),
                  icon: Icons.home_outlined,
                  title: 'Delivery address',
                  subtitle: 'Pick on the map for medicine deliveries',
                  path: '/settings/address',
                ),
                _NavTile(
                  key: const Key('settings-health'),
                  icon: Icons.medical_information_outlined,
                  title: 'Health profile',
                  subtitle: 'Allergies, conditions, lifestyle',
                  path: '/settings/health',
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Text('Preferences', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          Card(
            child: Column(
              children: [
                SwitchListTile(
                  key: const Key('pref-medication'),
                  secondary: const Icon(Icons.alarm_outlined),
                  title: const Text('Medication reminders'),
                  subtitle: const Text('Dose reminders and refill alerts'),
                  value: prefs.medicationReminders,
                  onChanged: user == null
                      ? null
                      : (v) => _setPrefs(
                          NotificationPrefs(
                            medicationReminders: v,
                            healthUpdates: prefs.healthUpdates,
                          ),
                        ),
                ),
                SwitchListTile(
                  key: const Key('pref-updates'),
                  secondary: const Icon(Icons.notifications_outlined),
                  title: const Text('Health updates'),
                  subtitle: const Text('Readings, risk changes, messages'),
                  value: prefs.healthUpdates,
                  onChanged: user == null
                      ? null
                      : (v) => _setPrefs(
                          NotificationPrefs(
                            medicationReminders: prefs.medicationReminders,
                            healthUpdates: v,
                          ),
                        ),
                ),
                const ListTile(
                  dense: true,
                  leading: Icon(Icons.priority_high),
                  title: Text(
                    'Urgent alerts (very high blood pressure, emergencies) are always sent.',
                  ),
                ),
                // Full width under its title, so the three labels never wrap.
                const ListTile(leading: Icon(Icons.palette_outlined), title: Text('Theme')),
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: ThemeModeSelector(expanded: true),
                ),
                if (user?.linkCode != null)
                  ListTile(
                    key: const Key('settings-link-code'),
                    leading: const Icon(Icons.family_restroom),
                    title: const Text('Family'),
                    subtitle: Text(
                      'Link code ${user!.linkCode} · approve requests, manage who follows you',
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => context.push('/family-requests'),
                  ),
                const _NavTile(
                  key: Key('settings-privacy'),
                  icon: Icons.shield_outlined,
                  title: 'Data & privacy',
                  subtitle: 'Export your data, delete your account',
                  path: '/settings/privacy',
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          FilledButton.tonalIcon(
            key: const Key('settings-sign-out'),
            style: FilledButton.styleFrom(
              backgroundColor: theme.colorScheme.errorContainer,
              foregroundColor: theme.colorScheme.onErrorContainer,
            ),
            onPressed: () => confirmAndSignOut(context, ref),
            icon: const Icon(Icons.logout),
            label: const Text('Sign out'),
          ),
          const SizedBox(height: 8),
          TextButton(
            key: const Key('settings-delete'),
            style: TextButton.styleFrom(foregroundColor: theme.colorScheme.error),
            onPressed: () => startAccountDeletion(context, ref),
            child: const Text('Delete account'),
          ),
        ],
      ),
    );
  }
}

class _ProfileHeader extends StatelessWidget {
  const _ProfileHeader({required this.user});

  final AppUser user;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final initial = user.name.trim().isEmpty ? '?' : user.name.trim()[0].toUpperCase();
    final shortId = user.uid.length <= 6 ? user.uid : user.uid.substring(0, 6);
    return Card(
      color: scheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            CircleAvatar(radius: 36, child: Text(initial, style: const TextStyle(fontSize: 28))),
            const SizedBox(height: 12),
            Text(user.name, style: Theme.of(context).textTheme.titleLarge),
            Text('Patient ID: #${shortId.toUpperCase()}'),
            const SizedBox(height: 8),
            FilledButton.tonal(
              key: const Key('settings-edit-profile'),
              onPressed: () => context.push('/settings/personal'),
              child: const Text('Edit profile'),
            ),
          ],
        ),
      ),
    );
  }
}

class _NavTile extends StatelessWidget {
  const _NavTile({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.path,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String path;

  @override
  Widget build(BuildContext context) => ListTile(
    leading: CircleAvatar(child: Icon(icon)),
    title: Text(title),
    subtitle: Text(subtitle),
    trailing: const Icon(Icons.chevron_right),
    onTap: () => context.push(path),
  );
}
