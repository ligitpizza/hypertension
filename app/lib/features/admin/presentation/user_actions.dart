import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/enums.dart';
import '../../../shared/services/api/api_client.dart';
import '../data/admin_repository.dart';
import '../state/admin_providers.dart';
import 'admin_users_page.dart' show roleLabel;

// User actions shared by User Management and the user detail page (UC11.1; D-59, D-60, D-61).
// Each returns true when the account changed, so the caller can refresh.

/// Runs an update and reports it; true when it succeeded.
Future<bool> _apply(BuildContext context, Future<AdminUser> Function() change, String done) async {
  final messenger = ScaffoldMessenger.of(context);
  try {
    await change();
    messenger.showSnackBar(SnackBar(content: Text(done)));
    return true;
  } on ApiException catch (e) {
    messenger.showSnackBar(SnackBar(content: Text(e.message)));
  } catch (_) {
    messenger.showSnackBar(const SnackBar(content: Text('Something went wrong. Try again.')));
  }
  return false;
}

Future<bool> editUser(BuildContext context, WidgetRef ref, AdminUser u) async {
  final result = await showDialog<_Edit>(
    context: context,
    builder: (_) => _EditDialog(user: u),
  );
  if (result == null || !context.mounted) return false;
  final repo = ref.read(adminRepositoryProvider);
  return _apply(
    context,
    () => repo.updateUser(
      u.uid,
      name: result.name,
      specialty: u.isDoctor ? result.specialty : null,
      maxPatients: u.isDoctor ? result.maxPatients : null,
    ),
    'Saved.',
  );
}

/// D-60: permanent removal, after typing DELETE.
Future<bool> deleteUser(BuildContext context, WidgetRef ref, AdminUser u) async {
  final typed = TextEditingController();
  final ok = await showDialog<bool>(
    context: context,
    builder: (c) => StatefulBuilder(
      builder: (c, setState) => AlertDialog(
        title: Text('Permanently delete ${u.name}?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              u.role == UserRole.patient
                  ? 'Their readings, medications, records, orders and messages to the AI agent '
                        'are deleted now. Notes, prescriptions and care plans written by doctors, '
                        'and the audit log, are kept. This cannot be undone.'
                  : 'Their login and account are removed. This cannot be undone. To keep '
                        'their history, deactivate instead.',
            ),
            const SizedBox(height: 8),
            TextField(
              key: const Key('delete-type'),
              controller: typed,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(labelText: 'Type DELETE to confirm'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(c).pop(false), child: const Text('Back')),
          FilledButton(
            key: const Key('delete-confirm'),
            style: FilledButton.styleFrom(backgroundColor: Theme.of(c).colorScheme.error),
            onPressed: typed.text.trim() == 'DELETE' ? () => Navigator.of(c).pop(true) : null,
            child: const Text('Delete'),
          ),
        ],
      ),
    ),
  );
  if (ok != true || !context.mounted) return false;
  final messenger = ScaffoldMessenger.of(context);
  try {
    await ref.read(adminRepositoryProvider).deleteUser(u.uid);
    messenger.showSnackBar(SnackBar(content: Text('${u.name} was deleted.')));
    return true;
  } on ApiException catch (e) {
    messenger.showSnackBar(SnackBar(content: Text(e.message)));
  } catch (_) {
    messenger.showSnackBar(const SnackBar(content: Text('Something went wrong. Try again.')));
  }
  return false;
}

Future<bool> toggleUserActive(BuildContext context, WidgetRef ref, AdminUser u) async {
  final repo = ref.read(adminRepositoryProvider);
  if (!u.isActive) {
    return _apply(
      context,
      () => repo.updateUser(u.uid, isActive: true),
      '${u.name} can sign in again.',
    );
  }
  final reason = TextEditingController();
  final ok = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text('Deactivate ${u.name}?'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('They are signed out everywhere and cannot sign in until reactivated.'),
          if (u.isDoctor && (u.caseload ?? 0) > 0)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                '${u.caseload} patients are assigned to this doctor. Reassign them through '
                'Assignments.',
                style: TextStyle(color: Theme.of(c).colorScheme.error),
              ),
            ),
          TextField(
            key: const Key('deactivate-reason'),
            controller: reason,
            maxLength: 300,
            decoration: const InputDecoration(labelText: 'Reason (optional, logged)'),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(c).pop(false), child: const Text('Back')),
        FilledButton(
          key: const Key('deactivate-confirm'),
          style: FilledButton.styleFrom(backgroundColor: Theme.of(c).colorScheme.error),
          onPressed: () => Navigator.of(c).pop(true),
          child: const Text('Deactivate'),
        ),
      ],
    ),
  );
  if (ok != true || !context.mounted) return false;
  return _apply(
    context,
    () => repo.updateUser(u.uid, isActive: false, reason: reason.text.trim()),
    '${u.name} was deactivated.',
  );
}

class _Edit {
  const _Edit(this.name, this.specialty, this.maxPatients);

  final String name;
  final String? specialty;
  final int? maxPatients;
}

class _EditDialog extends StatefulWidget {
  const _EditDialog({required this.user});

  final AdminUser user;

  @override
  State<_EditDialog> createState() => _EditDialogState();
}

class _EditDialogState extends State<_EditDialog> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.user.name);
  late final _specialty = TextEditingController(text: widget.user.specialty ?? '');
  late final _max = TextEditingController(text: '${widget.user.maxPatients ?? 30}');

  @override
  void dispose() {
    for (final c in [_name, _specialty, _max]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final u = widget.user;
    return AlertDialog(
      key: const Key('edit-user-dialog'),
      title: Text('Edit ${roleLabel(u.role).toLowerCase()}'),
      content: SizedBox(
        width: 400,
        child: Form(
          key: _form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(u.email, style: Theme.of(context).textTheme.bodySmall),
              TextFormField(
                key: const Key('edit-name'),
                controller: _name,
                decoration: const InputDecoration(labelText: 'Full name'),
                validator: (v) =>
                    (v ?? '').trim().length < 2 ? 'Enter at least 2 characters.' : null,
              ),
              if (u.isDoctor) ...[
                TextFormField(
                  key: const Key('edit-specialty'),
                  controller: _specialty,
                  decoration: const InputDecoration(labelText: 'Specialty'),
                ),
                TextFormField(
                  key: const Key('edit-max'),
                  controller: _max,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: InputDecoration(
                    labelText: 'Maximum patients',
                    helperText: 'Currently ${u.caseload ?? 0} assigned',
                  ),
                  validator: (v) {
                    final n = int.tryParse(v ?? '');
                    return n == null || n < 1 || n > 500 ? 'Enter 1 to 500.' : null;
                  },
                ),
              ],
              const SizedBox(height: 8),
              Text(
                'Roles cannot be changed. Create a new staff account instead.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
        FilledButton(
          key: const Key('edit-save'),
          onPressed: () {
            if (!_form.currentState!.validate()) return;
            Navigator.of(context).pop(
              _Edit(
                _name.text.trim(),
                u.isDoctor ? _specialty.text.trim() : null,
                u.isDoctor ? int.parse(_max.text) : null,
              ),
            );
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}
