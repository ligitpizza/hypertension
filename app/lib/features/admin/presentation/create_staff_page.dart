import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/enums.dart';
import '../../../core/utils/validators.dart';
import '../../../shared/providers/api_providers.dart';
import '../../../shared/services/api/api_client.dart';
import '../../auth/presentation/widgets/role_toggle.dart';

/// UC1.5 Create Staff Account (FR-1.6). Part of User Management (Fig 4.3.14.1);
/// the user list, edit and deactivate actions follow in Module 11.
class CreateStaffPage extends ConsumerStatefulWidget {
  const CreateStaffPage({super.key});

  @override
  ConsumerState<CreateStaffPage> createState() => _CreateStaffPageState();
}

class _CreateStaffPageState extends ConsumerState<CreateStaffPage> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _specialty = TextEditingController();
  UserRole _role = UserRole.doctor;
  bool _submitting = false;
  String? _error;
  Map<String, dynamic>? _result;

  @override
  void dispose() {
    for (final c in [_name, _email, _specialty]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _error = null;
      _result = null;
    });
    if (!_form.currentState!.validate()) return;
    setState(() => _submitting = true);
    try {
      final res = await ref
          .read(apiClientProvider)
          .createStaff(
            name: _name.text.trim(),
            email: _email.text.trim(),
            role: _role.value,
            specialty: _role == UserRole.doctor ? _specialty.text.trim() : null,
          );
      if (mounted) {
        setState(() => _result = {...res, 'email': _email.text.trim()});
        _form.currentState!.reset();
        _name.clear();
        _email.clear();
        _specialty.clear();
      }
    } on ApiException catch (e) {
      if (mounted) {
        setState(
          () => _error = e.code == 'EMAIL_ALREADY_REGISTERED'
              ? 'An account with this email already exists.' // UC1.5 E1
              : e.message,
        );
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Align(
        alignment: Alignment.topLeft,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Add staff account', style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 4),
              const Text(
                'Doctor, Pharmacist and Admin accounts are created here; '
                'these roles cannot register themselves.',
              ),
              const SizedBox(height: 20),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Form(
                    key: _form,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        RoleToggle(
                          roles: const [UserRole.doctor, UserRole.pharmacist, UserRole.admin],
                          selected: _role,
                          onChanged: (r) => setState(() => _role = r),
                          showIcons: false,
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          key: const Key('staff-name'),
                          controller: _name,
                          decoration: const InputDecoration(labelText: 'Full name'),
                          validator: Validators.name,
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          key: const Key('staff-new-email'),
                          controller: _email,
                          keyboardType: TextInputType.emailAddress,
                          decoration: const InputDecoration(labelText: 'Work email'),
                          validator: Validators.email,
                        ),
                        if (_role == UserRole.doctor) ...[
                          const SizedBox(height: 12),
                          TextFormField(
                            key: const Key('staff-specialty'),
                            controller: _specialty,
                            decoration: const InputDecoration(labelText: 'Specialty (optional)'),
                          ),
                        ],
                        const SizedBox(height: 20),
                        if (_error != null) ...[
                          Text(
                            _error!,
                            key: const Key('create-staff-error'),
                            style: TextStyle(color: scheme.error),
                          ),
                          const SizedBox(height: 8),
                        ],
                        FilledButton.icon(
                          key: const Key('create-staff-submit'),
                          onPressed: _submitting ? null : _submit,
                          icon: const Icon(Icons.person_add_alt_1),
                          label: const Text('Create account'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              if (_result != null) ...[const SizedBox(height: 16), _ResultCard(result: _result!)],
            ],
          ),
        ),
      ),
    );
  }
}

class _ResultCard extends StatelessWidget {
  const _ResultCard({required this.result});

  final Map<String, dynamic> result;

  @override
  Widget build(BuildContext context) {
    final sent = result['emailSent'] == true;
    final link = result['setupLink'] as String?;
    return Card(
      key: const Key('create-staff-result'),
      color: Theme.of(context).colorScheme.secondaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Account created for ${result['email']}',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            if (sent)
              const Text('A password setup link has been emailed to them.')
            else ...[
              const Text(
                'The setup email could not be sent. Share this one-time link '
                'with the staff member securely:',
              ),
              const SizedBox(height: 8),
              SelectableText(link ?? '', key: const Key('create-staff-link')),
              TextButton.icon(
                onPressed: link == null ? null : () => Clipboard.setData(ClipboardData(text: link)),
                icon: const Icon(Icons.copy),
                label: const Text('Copy link'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
