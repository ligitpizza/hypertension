import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/enums.dart';
import '../../../core/utils/validators.dart';
import '../data/auth_repository.dart';
import '../state/auth_providers.dart';
import 'widgets/role_toggle.dart';

/// Patient / Family mobile login (Fig 4.3.1.1, UC1.2). Role toggle per D-26;
/// biometrics deferred (not required by an FR).
class LoginPage extends ConsumerStatefulWidget {
  const LoginPage({super.key});

  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends ConsumerState<LoginPage> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  late UserRole _role;
  bool _obscure = true;
  bool _submitting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _role = ref.read(clientAppProvider) == ClientApp.family
        ? UserRole.familyMember
        : UserRole.patient;
  }

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
            app: ref.read(clientAppProvider),
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
    final isFamilyApp = ref.watch(clientAppProvider) == ClientApp.family;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                children: [
                  Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      color: scheme.primaryContainer,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Icon(Icons.favorite, color: scheme.onPrimaryContainer, size: 34),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    isFamilyApp ? 'CareFlow Family' : 'CareFlow',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Your health journey, beautifully managed.',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  Text('SELECT YOUR ROLE', style: Theme.of(context).textTheme.labelMedium),
                  const SizedBox(height: 8),
                  RoleToggle(
                    roles: const [UserRole.patient, UserRole.familyMember],
                    selected: _role,
                    onChanged: (r) => setState(() => _role = r),
                  ),
                  const SizedBox(height: 24),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Form(
                        key: _form,
                        child: AutofillGroup(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text(
                                'Welcome back',
                                textAlign: TextAlign.center,
                                style: Theme.of(context).textTheme.titleLarge,
                              ),
                              const SizedBox(height: 4),
                              const Text(
                                'Please enter your details to sign in.',
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 20),
                              TextFormField(
                                key: const Key('login-email'),
                                controller: _email,
                                keyboardType: TextInputType.emailAddress,
                                autofillHints: const [AutofillHints.email],
                                decoration: const InputDecoration(
                                  labelText: 'Email Address',
                                  prefixIcon: Icon(Icons.mail_outline),
                                ),
                                validator: Validators.email,
                              ),
                              const SizedBox(height: 12),
                              TextFormField(
                                key: const Key('login-password'),
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
                                  child: const Text('Forgot?'),
                                ),
                              ),
                              if (_error != null) ...[
                                Text(
                                  _error!,
                                  key: const Key('login-error'),
                                  style: TextStyle(color: scheme.error),
                                ),
                                const SizedBox(height: 8),
                              ],
                              FilledButton.icon(
                                key: const Key('login-submit'),
                                onPressed: _submitting ? null : _submit,
                                icon: _submitting
                                    ? const SizedBox(
                                        width: 18,
                                        height: 18,
                                        child: CircularProgressIndicator(strokeWidth: 2),
                                      )
                                    : const Icon(Icons.arrow_forward),
                                label: const Text('Sign In'),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Wrap(
                    alignment: WrapAlignment.center,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      const Text('New to CareFlow?'),
                      TextButton(
                        key: const Key('login-create-account'),
                        onPressed: () => context.go('/register'),
                        child: const Text('Create an account'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
