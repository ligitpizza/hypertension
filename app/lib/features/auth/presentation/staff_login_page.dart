import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/enums.dart';
import '../../../core/utils/validators.dart';
import '../../../shared/providers/api_providers.dart';
import '../data/auth_repository.dart';
import '../state/auth_providers.dart';
import 'widgets/role_toggle.dart';

/// Staff Portal login (Fig 4.3.14.8, UC1.2). Role toggle must match the
/// account's role claim (D-26). SSO is out of scope, so the button is omitted.
class StaffLoginPage extends ConsumerStatefulWidget {
  const StaffLoginPage({super.key});

  @override
  ConsumerState<StaffLoginPage> createState() => _StaffLoginPageState();
}

class _StaffLoginPageState extends ConsumerState<StaffLoginPage> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  UserRole _role = UserRole.doctor;
  bool _obscure = true;
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() => _error = null);
    if (!_form.currentState!.validate()) return;
    setState(() => _submitting = true);
    final busy = ref.read(authBusyProvider.notifier)..set(true);
    try {
      await ref
          .read(authRepositoryProvider)
          .signIn(
            email: _email.text,
            password: _password.text,
            selectedRole: _role,
            app: ClientApp.staff,
          );
    } on AuthFailure catch (f) {
      if (mounted) setState(() => _error = f.message);
    } catch (_) {
      if (mounted) setState(() => _error = AuthMessages.generic);
    } finally {
      busy.set(false);
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final health = ref.watch(apiHealthProvider);
    return Scaffold(
      backgroundColor: scheme.surfaceContainerLow,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Column(
              children: [
                Card(
                  elevation: 2,
                  child: Padding(
                    padding: const EdgeInsets.all(28),
                    child: Form(
                      key: _form,
                      child: AutofillGroup(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Center(
                              child: Container(
                                width: 52,
                                height: 52,
                                decoration: BoxDecoration(
                                  color: scheme.primaryContainer,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Icon(
                                  Icons.medical_services,
                                  color: scheme.onPrimaryContainer,
                                ),
                              ),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              'CareFlow Pro',
                              textAlign: TextAlign.center,
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                            const Text('Secure Staff Portal', textAlign: TextAlign.center),
                            const SizedBox(height: 20),
                            Center(
                              child: RoleToggle(
                                roles: const [UserRole.doctor, UserRole.admin, UserRole.pharmacist],
                                selected: _role,
                                onChanged: (r) => setState(() => _role = r),
                                showIcons: false,
                              ),
                            ),
                            const SizedBox(height: 20),
                            TextFormField(
                              key: const Key('staff-email'),
                              controller: _email,
                              keyboardType: TextInputType.emailAddress,
                              autofillHints: const [AutofillHints.email],
                              decoration: const InputDecoration(
                                labelText: 'Staff Email',
                                prefixIcon: Icon(Icons.mail_outline),
                              ),
                              validator: Validators.email,
                            ),
                            const SizedBox(height: 12),
                            TextFormField(
                              key: const Key('staff-password'),
                              controller: _password,
                              obscureText: _obscure,
                              autofillHints: const [AutofillHints.password],
                              decoration: InputDecoration(
                                labelText: 'Password',
                                prefixIcon: const Icon(Icons.lock_outline),
                                suffixIcon: IconButton(
                                  tooltip: _obscure ? 'Show password' : 'Hide password',
                                  icon: Icon(_obscure ? Icons.visibility : Icons.visibility_off),
                                  onPressed: () => setState(() => _obscure = !_obscure),
                                ),
                              ),
                              validator: (v) => Validators.requiredText(v, label: 'Password'),
                              onFieldSubmitted: (_) => _submit(),
                            ),
                            Align(
                              alignment: Alignment.centerRight,
                              child: TextButton(
                                onPressed: () => context.push('/forgot-password'),
                                child: const Text('Forgot Password?'),
                              ),
                            ),
                            if (_error != null) ...[
                              Text(
                                _error!,
                                key: const Key('staff-login-error'),
                                style: TextStyle(color: scheme.error),
                              ),
                              const SizedBox(height: 8),
                            ],
                            FilledButton.icon(
                              key: const Key('staff-login-submit'),
                              onPressed: _submitting ? null : _submit,
                              icon: const Icon(Icons.arrow_forward),
                              label: const Text('Sign In'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  health.when(
                    data: (_) => 'System Status: All Operational',
                    loading: () => 'System Status: checking…',
                    error: (_, _) => 'System Status: API unreachable',
                  ),
                  key: const Key('staff-system-status'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
