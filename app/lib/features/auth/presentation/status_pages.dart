import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/enums.dart';
import '../../../shared/providers/api_providers.dart';
import '../data/auth_repository.dart';
import '../state/auth_providers.dart';

/// Shown while Firebase restores the session or the profile loads.
class SplashPage extends StatelessWidget {
  const SplashPage({super.key});

  @override
  Widget build(BuildContext context) => const Scaffold(
    body: Center(child: CircularProgressIndicator(semanticsLabel: 'Loading')),
  );
}

class _MessagePage extends ConsumerWidget {
  const _MessagePage({required this.icon, required this.title, required this.message, this.extra});

  final IconData icon;
  final String title;
  final String message;
  final Widget? extra;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 56),
                const SizedBox(height: 16),
                Text(title, style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 8),
                Text(message, textAlign: TextAlign.center),
                const SizedBox(height: 24),
                if (extra != null) ...[extra!, const SizedBox(height: 12)],
                OutlinedButton(
                  onPressed: () =>
                      ref.read(authRepositoryProvider).signOut(ref.read(clientAppProvider)),
                  child: const Text('Sign out'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// UC1.2 E2: account deactivated by the Admin.
class DeactivatedPage extends StatelessWidget {
  const DeactivatedPage({super.key});

  @override
  Widget build(BuildContext context) => const _MessagePage(
    icon: Icons.block,
    title: 'Account deactivated',
    message: AuthMessages.deactivated,
  );
}

/// NFR-3.2 / D-26: the account belongs to a different app.
class WrongAppPage extends ConsumerWidget {
  const WrongAppPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final role = ref.watch(currentUserProvider).value?.role;
    return _MessagePage(
      icon: Icons.swap_horiz,
      title: 'Wrong app',
      message: wrongAppMessage(role, ref.watch(clientAppProvider)) ?? AuthMessages.generic,
    );
  }
}

/// UC1.1 step 3 recovery: Firebase account exists but the profile was not created
/// (e.g. connection lost). register-profile is idempotent, so just retry.
class FinishRegistrationPage extends ConsumerStatefulWidget {
  const FinishRegistrationPage({super.key});

  @override
  ConsumerState<FinishRegistrationPage> createState() => _FinishRegistrationPageState();
}

class _FinishRegistrationPageState extends ConsumerState<FinishRegistrationPage> {
  bool _working = false;
  String? _error;

  Future<void> _retry() async {
    setState(() {
      _working = true;
      _error = null;
    });
    final app = ref.read(clientAppProvider);
    final user = FirebaseAuth.instance.currentUser;
    try {
      await ref
          .read(apiClientProvider)
          .registerProfile(
            name: (user?.displayName?.trim().length ?? 0) >= 2
                ? user!.displayName!
                : 'CareFlow user',
            role: app == ClientApp.family ? UserRole.familyMember.value : UserRole.patient.value,
          );
      await user?.getIdToken(true);
    } catch (_) {
      if (mounted) setState(() => _error = AuthMessages.network);
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (ref.watch(clientAppProvider) == ClientApp.staff) {
      // Staff accounts are created by the Admin (FR-1.6); never self-repair them.
      return const _MessagePage(
        icon: Icons.manage_accounts_outlined,
        title: 'Account not set up',
        message: 'Your staff account is incomplete. Please contact your administrator.',
      );
    }
    return _MessagePage(
      icon: Icons.manage_accounts_outlined,
      title: 'Finish setting up',
      message: _error ?? 'We could not finish creating your account. Please try again.',
      extra: FilledButton(onPressed: _working ? null : _retry, child: const Text('Try again')),
    );
  }
}
