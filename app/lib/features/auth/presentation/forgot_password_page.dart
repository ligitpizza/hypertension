import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../shared/services/api/api_client.dart';
import '../../../core/utils/validators.dart';
import '../state/auth_providers.dart';

/// UC1.2 A1: send a password reset link, then return to login.
class ForgotPasswordPage extends ConsumerStatefulWidget {
  const ForgotPasswordPage({super.key});

  @override
  ConsumerState<ForgotPasswordPage> createState() => _ForgotPasswordPageState();
}

class _ForgotPasswordPageState extends ConsumerState<ForgotPasswordPage> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  bool _sending = false;
  bool _sent = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      await ref.read(authRepositoryProvider).sendPasswordReset(_email.text);
    } on ApiException catch (e) {
      if (e.code == 'RATE_LIMITED') {
        if (mounted) {
          setState(() {
            _sending = false;
            _error = 'Too many requests. Please wait a minute and try again.';
          });
        }
        return;
      }
      // Anything else: same message whether or not the email exists (no enumeration).
    } catch (_) {}
    if (mounted) {
      setState(() {
        _sending = false;
        _sent = true;
      });
    }
  }

  void _back() => context.canPop() ? context.pop() : context.go('/login');

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Reset password'),
        leading: BackButton(onPressed: _back),
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: _sent
                ? Column(
                    key: const Key('reset-sent'),
                    children: [
                      const Icon(Icons.mark_email_read_outlined, size: 56),
                      const SizedBox(height: 16),
                      const Text(
                        'If an account exists for that email, a reset link from Harvey is on '
                        'its way (check spam too). The link works for 1 hour. Choose a new '
                        'password there, then come back and sign in.',
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 24),
                      FilledButton(onPressed: _back, child: const Text('Back to sign in')),
                    ],
                  )
                : Form(
                    key: _form,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Text(
                          'Enter your email and we will send you a link to reset '
                          'your password.',
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          key: const Key('reset-email'),
                          controller: _email,
                          keyboardType: TextInputType.emailAddress,
                          decoration: const InputDecoration(labelText: 'Email address'),
                          validator: Validators.email,
                        ),
                        if (_error != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Text(
                              _error!,
                              key: const Key('reset-error'),
                              style: TextStyle(color: Theme.of(context).colorScheme.error),
                            ),
                          ),
                        const SizedBox(height: 20),
                        FilledButton(
                          key: const Key('reset-submit'),
                          onPressed: _sending ? null : _send,
                          child: const Text('Send reset link'),
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
