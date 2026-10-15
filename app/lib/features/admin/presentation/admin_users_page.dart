import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/enums.dart';
import '../../../shared/services/api/api_client.dart';
import '../../provider_portal/presentation/portal_widgets.dart' show formatDate;
import '../data/admin_repository.dart';
import '../state/admin_providers.dart';

const _pageSize = 10;

String roleLabel(UserRole? r) => switch (r) {
  UserRole.patient => 'Patient',
  UserRole.doctor => 'Doctor',
  UserRole.pharmacist => 'Pharmacist',
  UserRole.admin => 'Admin',
  UserRole.familyMember => 'Family',
  null => 'No role',
};

/// User Management (Fig 4.3.14.1; FR-11.1, UC11.1; D-59): search, filter by role,
/// edit, deactivate / reactivate. "Add new user" opens staff provisioning (UC1.5).
class AdminUsersPage extends ConsumerStatefulWidget {
  const AdminUsersPage({super.key});

  @override
  ConsumerState<AdminUsersPage> createState() => _AdminUsersPageState();
}

class _AdminUsersPageState extends ConsumerState<AdminUsersPage> {
  final _search = TextEditingController();
  UserRole? _role;
  String _query = '';
  int _page = 0;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _refresh() => ref.invalidate(adminUsersProvider((_role, _query)));

  Future<void> _apply(Future<AdminUser> Function() change, String done) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await change();
      messenger.showSnackBar(SnackBar(content: Text(done)));
      _refresh();
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      messenger.showSnackBar(const SnackBar(content: Text('Something went wrong. Try again.')));
    }
  }

  Future<void> _edit(AdminUser u) async {
    final result = await showDialog<_Edit>(
      context: context,
      builder: (_) => _EditDialog(user: u),
    );
    if (result == null) return;
    final repo = ref.read(adminRepositoryProvider);
    await _apply(
      () => repo.updateUser(
        u.uid,
        name: result.name,
        specialty: u.isDoctor ? result.specialty : null,
        maxPatients: u.isDoctor ? result.maxPatients : null,
      ),
      'Saved.',
    );
  }

  /// D-60: open a patient account; the setup link is shown if it could not be emailed.
  Future<void> _createPatient() async {
    final created = await showDialog<(String, String?)>(
      context: context,
      builder: (_) => const _PatientDialog(),
    );
    if (created == null || !mounted) return;
    _refresh();
    final (name, link) = created;
    if (link == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Account created. $name was emailed a setup link.')));
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Account created'),
        content: SelectableText(
          'The email could not be sent. Give $name this link to set a password:\n\n$link',
          key: const Key('patient-setup-link'),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: link));
              Navigator.of(c).pop();
            },
            child: const Text('Copy and close'),
          ),
        ],
      ),
    );
  }

  /// D-60: permanent removal, after typing DELETE.
  Future<void> _delete(AdminUser u) async {
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
    if (ok != true || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(adminRepositoryProvider).deleteUser(u.uid);
      messenger.showSnackBar(SnackBar(content: Text('${u.name} was deleted.')));
      _refresh();
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      messenger.showSnackBar(const SnackBar(content: Text('Something went wrong. Try again.')));
    }
  }

  Future<void> _toggleActive(AdminUser u) async {
    final repo = ref.read(adminRepositoryProvider);
    if (!u.isActive) {
      await _apply(() => repo.updateUser(u.uid, isActive: true), '${u.name} can sign in again.');
      return;
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
    if (ok != true) return;
    await _apply(
      () => repo.updateUser(u.uid, isActive: false, reason: reason.text.trim()),
      '${u.name} was deactivated.',
    );
  }

  @override
  Widget build(BuildContext context) {
    final users = ref.watch(adminUsersProvider((_role, _query)));
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Wrap(
          spacing: 16,
          runSpacing: 12,
          crossAxisAlignment: WrapCrossAlignment.center,
          alignment: WrapAlignment.spaceBetween,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('User Management', style: theme.textTheme.headlineSmall),
                const Text('Manage all system users, roles, and access statuses.'),
              ],
            ),
            SizedBox(
              width: 280,
              child: TextField(
                key: const Key('user-search'),
                controller: _search,
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  hintText: 'Search users…',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                onSubmitted: (v) => setState(() {
                  _query = v.trim();
                  _page = 0;
                }),
              ),
            ),
            MenuAnchor(
              builder: (context, controller, _) => FilledButton.icon(
                key: const Key('add-user'),
                onPressed: () => controller.isOpen ? controller.close() : controller.open(),
                icon: const Icon(Icons.add),
                label: const Text('Add new user'),
              ),
              menuChildren: [
                MenuItemButton(
                  key: const Key('add-staff'),
                  leadingIcon: const Icon(Icons.badge_outlined),
                  onPressed: () => context.push('/admin/users/new'),
                  child: const Text('Staff account'),
                ),
                MenuItemButton(
                  key: const Key('add-patient'),
                  leadingIcon: const Icon(Icons.person_add_alt),
                  onPressed: _createPatient,
                  child: const Text('Patient account'),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(child: Text('System users', style: theme.textTheme.titleLarge)),
                    const Text('Filter by role: '),
                    DropdownButton<UserRole?>(
                      key: const Key('role-filter'),
                      value: _role,
                      items: [
                        const DropdownMenuItem(child: Text('All roles')),
                        for (final r in UserRole.values)
                          DropdownMenuItem(value: r, child: Text(roleLabel(r))),
                      ],
                      onChanged: (r) => setState(() {
                        _role = r;
                        _page = 0;
                      }),
                    ),
                  ],
                ),
                const Divider(),
                users.when(
                  loading: () => const Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(child: CircularProgressIndicator()),
                  ),
                  error: (_, _) => ListTile(
                    leading: const Icon(Icons.cloud_off),
                    title: const Text('Could not load users.'),
                    trailing: TextButton(onPressed: _refresh, child: const Text('Retry')),
                  ),
                  data: (all) {
                    if (all.isEmpty) {
                      return const Padding(
                        padding: EdgeInsets.all(16),
                        child: Text('No users match.', key: Key('no-users')),
                      );
                    }
                    final pages = (all.length / _pageSize).ceil();
                    final page = _page.clamp(0, pages - 1);
                    final shown = all.skip(page * _pageSize).take(_pageSize).toList();
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (final u in shown)
                          _UserRow(
                            user: u,
                            onEdit: () => _edit(u),
                            onToggle: () => _toggleActive(u),
                            onDelete: () => _delete(u),
                          ),
                        const Divider(),
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                'Showing ${page * _pageSize + 1} to '
                                '${page * _pageSize + shown.length} of ${all.length} entries',
                                key: const Key('users-count'),
                              ),
                            ),
                            IconButton(
                              key: const Key('users-prev'),
                              icon: const Icon(Icons.chevron_left),
                              onPressed: page > 0 ? () => setState(() => _page = page - 1) : null,
                            ),
                            Text('${page + 1} / $pages'),
                            IconButton(
                              key: const Key('users-next'),
                              icon: const Icon(Icons.chevron_right),
                              onPressed: page < pages - 1
                                  ? () => setState(() => _page = page + 1)
                                  : null,
                            ),
                          ],
                        ),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _UserRow extends StatelessWidget {
  const _UserRow({
    required this.user,
    required this.onEdit,
    required this.onToggle,
    required this.onDelete,
  });

  final AdminUser user;
  final VoidCallback onEdit;
  final VoidCallback onToggle;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final u = user;
    final status = !u.isActive
        ? (u.deletionRequested ? 'Deletion pending' : 'Deactivated')
        : 'Active';
    final statusColor = u.isActive ? Colors.green.shade700 : Colors.red.shade700;
    final initials = u.name.trim().isEmpty
        ? '?'
        : u.name.trim().split(RegExp(r'\s+')).take(2).map((w) => w[0].toUpperCase()).join();
    return ListTile(
      key: Key('user-${u.uid}'),
      leading: CircleAvatar(child: Text(initials)),
      title: Text(u.name.isEmpty ? '(no name)' : u.name),
      subtitle: Text(
        [
          u.email,
          if (u.isDoctor)
            '${u.specialty ?? 'Doctor'} · ${u.caseload ?? 0} / ${u.maxPatients} patients',
        ].join('\n'),
      ),
      isThreeLine: u.isDoctor,
      trailing: Wrap(
        spacing: 12,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Chip(label: Text(roleLabel(u.role)), visualDensity: VisualDensity.compact),
          Text(
            '● $status',
            key: Key('status-${u.uid}'),
            style: TextStyle(color: statusColor, fontWeight: FontWeight.w600),
          ),
          SizedBox(
            width: 110,
            child: Text(u.createdAt == null ? '-' : formatDate(u.createdAt!).split(',').first),
          ),
          PopupMenuButton<String>(
            key: Key('user-menu-${u.uid}'),
            onSelected: (a) => switch (a) {
              'edit' => onEdit(),
              'delete' => onDelete(),
              _ => onToggle(),
            },
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'edit', child: Text('Edit')),
              PopupMenuItem(value: 'toggle', child: Text(u.isActive ? 'Deactivate' : 'Reactivate')),
              const PopupMenuItem(value: 'delete', child: Text('Delete permanently')),
            ],
          ),
        ],
      ),
    );
  }
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

/// D-60: name, email and IC (the IC fills the date of birth and gender, D-51).
class _PatientDialog extends ConsumerStatefulWidget {
  const _PatientDialog();

  @override
  ConsumerState<_PatientDialog> createState() => _PatientDialogState();
}

class _PatientDialogState extends ConsumerState<_PatientDialog> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _ic = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    for (final c in [_name, _email, _ic]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final link = await ref
          .read(adminRepositoryProvider)
          .createPatient(
            name: _name.text.trim(),
            email: _email.text.trim(),
            icNumber: _ic.text.trim(),
          );
      if (mounted) Navigator.of(context).pop((_name.text.trim(), link));
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } catch (_) {
      setState(() => _error = 'Something went wrong. Try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    key: const Key('patient-dialog'),
    title: const Text('Create patient account'),
    content: SizedBox(
      width: 400,
      child: Form(
        key: _form,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              key: const Key('patient-name'),
              controller: _name,
              decoration: const InputDecoration(labelText: 'Full name'),
              validator: (v) => (v ?? '').trim().length < 2 ? 'Enter the full name.' : null,
            ),
            TextFormField(
              key: const Key('patient-email'),
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(labelText: 'Email'),
              validator: (v) => RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch((v ?? '').trim())
                  ? null
                  : 'Enter a valid email.',
            ),
            TextFormField(
              key: const Key('patient-ic'),
              controller: _ic,
              decoration: const InputDecoration(labelText: 'IC number', hintText: '900101-14-5677'),
              validator: (v) => RegExp(r'^\d{6}-?\d{2}-?\d{4}$').hasMatch((v ?? '').trim())
                  ? null
                  : 'Enter a 12-digit IC number.',
            ),
            const SizedBox(height: 8),
            Text(
              'A setup link is emailed. The patient signs in to the app and completes their '
              'health profile; a doctor request is then created automatically.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  _error!,
                  key: const Key('patient-error'),
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
      FilledButton(
        key: const Key('patient-save'),
        onPressed: _busy ? null : _save,
        child: const Text('Create'),
      ),
    ],
  );
}
