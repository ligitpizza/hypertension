import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'widgets/role_toggle.dart';
import '../../../core/constants/enums.dart';
import '../../../shared/providers/api_providers.dart';
import '../data/auth_repository.dart';
import '../state/auth_providers.dart';
import '../../../shared/services/api/api_client.dart';
import '../../../core/utils/ic_number.dart';

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
  final _ic = TextEditingController(); // D-51: patients must give it to finish

  /// D-63: the Harvey app may finish a patient or a family-member account.
  late UserRole _role = ref.read(clientAppProvider) == ClientApp.family
      ? UserRole.familyMember
      : UserRole.patient;

  @override
  void dispose() {
    _ic.dispose();
    super.dispose();
  }

  Future<void> _retry() async {
    setState(() {
      _working = true;
      _error = null;
    });
    final user = FirebaseAuth.instance.currentUser;
    final patient = _role == UserRole.patient;
    final icError = patient ? validateIc(_ic.text) : null;
    if (icError != null) {
      setState(() {
        _working = false;
        _error = icError;
      });
      return;
    }
    try {
      await ref
          .read(apiClientProvider)
          .registerProfile(
            name: (user?.displayName?.trim().length ?? 0) >= 2 ? user!.displayName! : 'Harvey user',
            role: _role.value,
            icNumber: patient ? parseIc(_ic.text).value : null,
          );
      await user?.getIdToken(true);
    } on ApiException catch (e) {
      if (mounted) {
        setState(() => _error = e.code.contains('IC') ? e.message : AuthMessages.network);
      }
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
      extra: Column(
        children: [
          if (ref.watch(clientAppProvider) == ClientApp.patient) ...[
            RoleToggle(
              key: const Key('finish-role'),
              roles: const [UserRole.patient, UserRole.familyMember],
              selected: _role,
              onChanged: (r) => setState(() => _role = r),
            ),
            const SizedBox(height: 12),
          ],
          if (_role == UserRole.patient) ...[
            SizedBox(
              width: 280,
              child: TextField(
                key: const Key('finish-ic'),
                controller: _ic,
                keyboardType: TextInputType.number,
                inputFormatters: [IcInputFormatter()],
                decoration: const InputDecoration(labelText: 'IC number (MyKad)'),
              ),
            ),
            const SizedBox(height: 12),
          ],
          FilledButton(onPressed: _working ? null : _retry, child: const Text('Try again')),
        ],
      ),
    );
  }
}
