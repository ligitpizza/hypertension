import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/enums.dart';
import '../../core/theme/theme_mode.dart';
import '../../shared/providers/api_providers.dart';
import '../../shared/services/api/api_client.dart';
import '../auth/state/auth_providers.dart';
import '../notifications/data/notifications_repository.dart';
import '../notifications/state/notification_providers.dart';

/// D-77: the signed-in staff member's own details.
final staffProfileProvider = FutureProvider.autoDispose<Map<String, dynamic>>(
  (ref) => ref.watch(apiClientProvider).staffProfile(),
  retry: (_, _) => null,
);

/// D-77 portal Settings (doctor, pharmacist, admin): profile, password, appearance and
/// which notifications reach the bell.
class StaffSettingsPage extends ConsumerWidget {
  const StaffSettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(staffProfileProvider);
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text('Settings', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 16),
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _Section(
                  icon: Icons.person_outline,
                  title: 'Profile',
                  child: profile.when(
                    loading: () => const LinearProgressIndicator(),
                    error: (_, _) => TextButton(
                      onPressed: () => ref.invalidate(staffProfileProvider),
                      child: const Text('Could not load your profile. Retry'),
                    ),
                    data: (p) => _ProfileForm(profile: p),
                  ),
                ),
                _Section(
                  icon: Icons.lock_outline,
                  title: 'Password',
                  child: _PasswordReset(email: profile.value?['email'] as String?),
                ),
                const _Section(
                  icon: Icons.palette_outlined,
                  title: 'Appearance',
                  child: ThemeModeSelector(expanded: true),
                ),
                const _Section(
                  icon: Icons.notifications_none,
                  title: 'Notifications in the bell',
                  child: _BellPrefs(),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.icon, required this.title, required this.child});
  final IconData icon;
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) => Card(
    margin: const EdgeInsets.only(bottom: 16),
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(icon, color: Theme.of(context).colorScheme.primary),
              const SizedBox(width: 8),
              Text(title, style: Theme.of(context).textTheme.titleMedium),
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    ),
  );
}

class _ProfileForm extends ConsumerStatefulWidget {
  const _ProfileForm({required this.profile});
  final Map<String, dynamic> profile;

  @override
  ConsumerState<_ProfileForm> createState() => _ProfileFormState();
}

class _ProfileFormState extends ConsumerState<_ProfileForm> {
  late final _name = TextEditingController(text: widget.profile['name'] as String? ?? '');
  late final _phone = TextEditingController(text: widget.profile['phone'] as String? ?? '');
  late final _specialty = TextEditingController(text: widget.profile['specialty'] as String? ?? '');
  bool _saving = false;

  bool get _doctor => widget.profile['role'] == UserRole.doctor.value;

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _specialty.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final messenger = ScaffoldMessenger.of(context);
    if (_name.text.trim().length < 2) {
      messenger.showSnackBar(const SnackBar(content: Text('Enter your name.')));
      return;
    }
    setState(() => _saving = true);
    try {
      await ref
          .read(apiClientProvider)
          .updateStaffProfile(
            name: _name.text.trim(),
            phone: _phone.text.trim().isEmpty ? null : _phone.text.trim(),
            specialty: _doctor && _specialty.text.trim().isNotEmpty ? _specialty.text.trim() : null,
          );
      ref.invalidate(staffProfileProvider);
      messenger.showSnackBar(const SnackBar(content: Text('Profile saved.')));
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text('Email: ${widget.profile['email'] ?? '-'} (sign-in email, set by the admin)'),
      const SizedBox(height: 12),
      TextField(
        key: const Key('staff-name'),
        controller: _name,
        decoration: const InputDecoration(labelText: 'Full name', border: OutlineInputBorder()),
      ),
      const SizedBox(height: 12),
      TextField(
        key: const Key('staff-phone'),
        controller: _phone,
        keyboardType: TextInputType.phone,
        decoration: const InputDecoration(
          labelText: 'Phone (optional)',
          hintText: '012-345 6789',
          border: OutlineInputBorder(),
        ),
      ),
      if (_doctor) ...[
        const SizedBox(height: 12),
        TextField(
          key: const Key('staff-specialty'),
          controller: _specialty,
          decoration: const InputDecoration(labelText: 'Specialty', border: OutlineInputBorder()),
        ),
      ],
      const SizedBox(height: 12),
      Align(
        alignment: Alignment.centerRight,
        child: FilledButton.icon(
          key: const Key('staff-profile-save'),
          onPressed: _saving ? null : _save,
          icon: const Icon(Icons.save_outlined),
          label: const Text('Save profile'),
        ),
      ),
    ],
  );
}

class _PasswordReset extends ConsumerStatefulWidget {
  const _PasswordReset({required this.email});
  final String? email;

  @override
  ConsumerState<_PasswordReset> createState() => _PasswordResetState();
}

class _PasswordResetState extends ConsumerState<_PasswordReset> {
  bool _sent = false;

  Future<void> _send() async {
    final email = widget.email;
    if (email == null) return;
    try {
      await ref.read(authRepositoryProvider).sendPasswordReset(email);
      setState(() => _sent = true);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not send the email. Please try again.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        _sent
            ? 'We sent a link to ${widget.email}. Open it to choose a new password.'
            : 'We will email you a secure link to choose a new password.',
        key: const Key('staff-password-note'),
      ),
      const SizedBox(height: 8),
      OutlinedButton.icon(
        key: const Key('staff-password-reset'),
        onPressed: widget.email == null || _sent ? null : _send,
        icon: const Icon(Icons.mail_outline),
        label: const Text('Send password reset email'),
      ),
    ],
  );
}

class _BellPrefs extends ConsumerWidget {
  const _BellPrefs();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final prefs = ref.watch(bellPrefsProvider);
    return prefs.when(
      loading: () => const LinearProgressIndicator(),
      error: (_, _) => TextButton(
        onPressed: () => ref.invalidate(bellPrefsProvider),
        child: const Text('Could not load. Retry'),
      ),
      data: (p) => Column(
        children: [
          for (final e in bellCategories.entries)
            SwitchListTile(
              key: Key('bell-pref-${e.key}'),
              contentPadding: EdgeInsets.zero,
              title: Text(e.value),
              value: p[e.key] ?? true,
              onChanged: (v) async {
                await ref.read(notificationsRepositoryProvider).savePrefs({...p, e.key: v});
                ref.invalidate(bellPrefsProvider);
              },
            ),
          Text(
            'Urgent alerts always reach the bell.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}
