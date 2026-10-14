import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/enums.dart';
import '../../../core/utils/validators.dart';
import '../data/auth_repository.dart';
import '../state/auth_providers.dart';
import '../../../core/utils/ic_number.dart';
import 'onboarding/onboarding_labels.dart';

/// UC1.1 Register Account (FR-1.1). Patient app registers patients, Family app
/// registers family members; staff never self-register (FR-1.6).
class RegisterPage extends ConsumerStatefulWidget {
  const RegisterPage({super.key});

  @override
  ConsumerState<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends ConsumerState<RegisterPage> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  final _ic = TextEditingController();

  /// "Born 1 Jan 1990 · Male" once the IC is complete and valid.
  String? _icPreview() {
    try {
      final ic = parseIc(_ic.text);
      const months = [
        'Jan',
        'Feb',
        'Mar',
        'Apr',
        'May',
        'Jun',
        'Jul',
        'Aug',
        'Sep',
        'Oct',
        'Nov',
        'Dec',
      ];
      final d = ic.dateOfBirth;
      return 'Born ${d.day} ${months[d.month - 1]} ${d.year} · ${OnboardingLabels.gender(ic.gender)}';
    } on FormatException {
      return null;
    }
  }

  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    for (final c in [_name, _ic, _email, _password, _confirm]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() => _error = null);
    if (!_form.currentState!.validate()) return;
    setState(() => _submitting = true);
    final app = ref.read(clientAppProvider);
    final role = app == ClientApp.family ? UserRole.familyMember : UserRole.patient;
    final busy = ref.read(authBusyProvider.notifier)..set(true);
    try {
      await ref
          .read(authRepositoryProvider)
          .register(
            name: _name.text,
            email: _email.text,
            password: _password.text,
            role: role,
            icNumber: role == UserRole.patient ? parseIc(_ic.text).value : null,
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
    final isFamily = ref.watch(clientAppProvider) == ClientApp.family;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Create an account'),
        leading: BackButton(onPressed: () => context.go('/login')),
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Form(
                key: _form,
                child: AutofillGroup(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        isFamily
                            ? 'Register as a family member to follow a loved one\'s health.'
                            : 'Register as a patient to start tracking your blood pressure.',
                      ),
                      const SizedBox(height: 20),
                      TextFormField(
                        key: const Key('register-name'),
                        controller: _name,
                        textCapitalization: TextCapitalization.words,
                        autofillHints: const [AutofillHints.name],
                        decoration: const InputDecoration(labelText: 'Full name'),
                        validator: Validators.name,
                      ),
                      const SizedBox(height: 12),
                      if (!isFamily) ...[
                        // D-51: MyKad number; date of birth and gender come from it later.
                        TextFormField(
                          key: const Key('register-ic'),
                          controller: _ic,
                          keyboardType: TextInputType.number,
                          inputFormatters: [IcInputFormatter()],
                          decoration: InputDecoration(
                            labelText: 'IC number (MyKad)',
                            hintText: '900101-14-5678',
                            helperText: _icPreview(),
                          ),
                          onChanged: (_) => setState(() {}),
                          // Clear the error as soon as the number is corrected.
                          autovalidateMode: AutovalidateMode.onUserInteraction,
                          validator: validateIc,
                        ),
                        const SizedBox(height: 12),
                      ],
                      TextFormField(
                        key: const Key('register-email'),
                        controller: _email,
                        keyboardType: TextInputType.emailAddress,
                        autofillHints: const [AutofillHints.email],
                        decoration: const InputDecoration(labelText: 'Email address'),
                        validator: Validators.email,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        key: const Key('register-password'),
                        controller: _password,
                        obscureText: true,
                        autofillHints: const [AutofillHints.newPassword],
                        decoration: const InputDecoration(
                          labelText: 'Password',
                          helperText: Validators.passwordRule,
                        ),
                        validator: Validators.password,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        key: const Key('register-confirm'),
                        controller: _confirm,
                        obscureText: true,
                        decoration: const InputDecoration(labelText: 'Confirm password'),
                        validator: (v) => v == _password.text ? null : 'Passwords do not match.',
                      ),
                      const SizedBox(height: 20),
                      if (_error != null) ...[
                        Text(
                          _error!,
                          key: const Key('register-error'),
                          style: TextStyle(color: scheme.error),
                        ),
                        if (_error == AuthMessages.emailInUse)
                          TextButton(
                            onPressed: () => context.go('/login'),
                            child: const Text('Go to sign in'),
                          ),
                        const SizedBox(height: 8),
                      ],
                      FilledButton(
                        key: const Key('register-submit'),
                        onPressed: _submitting ? null : _submit,
                        child: _submitting
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Text('Create account'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
