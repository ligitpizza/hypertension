import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/enums.dart';
import '../../../core/utils/risk_style.dart';
import '../../appointments/domain/appointment_text.dart' show dateLabel, timeLabel;
import '../../provider_portal/presentation/portal_widgets.dart' show formatDate;
import '../data/admin_repository.dart';
import '../state/admin_providers.dart';
import 'admin_users_page.dart' show roleLabel;
import 'audit_logs_page.dart' show actionLabel;
import 'user_actions.dart';

Map<String, dynamic> _map(Object? v) => Map<String, dynamic>.from(v as Map? ?? const {});

List<Map<String, dynamic>> _list(Object? v) => [
  for (final e in (v as List? ?? const [])) Map<String, dynamic>.from(e as Map),
];

DateTime? _time(Object? v) => v == null ? null : DateTime.tryParse('$v');

String _when(Object? v) {
  final t = _time(v);
  return t == null ? '-' : '${dateLabel(t)}, ${timeLabel(t)}';
}

RiskLevel? _level(Object? v) => v == null ? null : RiskLevel.fromValue('$v');

String _levelName(RiskLevel l) => switch (l) {
  RiskLevel.low => 'Low',
  RiskLevel.moderate => 'Moderate',
  RiskLevel.high => 'High',
  RiskLevel.critical => 'Critical',
};

/// D-61: one patient, doctor, pharmacist (or other user) for the admin.
class AdminUserDetailPage extends ConsumerWidget {
  const AdminUserDetailPage({super.key, required this.uid});

  final String uid;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detail = ref.watch(adminUserDetailProvider(uid));
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            key: const Key('detail-back'),
            onPressed: () => context.canPop() ? context.pop() : context.go('/admin/users'),
            icon: const Icon(Icons.arrow_back),
            label: const Text('User management'),
          ),
        ),
        detail.when(
          loading: () => const Padding(
            padding: EdgeInsets.all(32),
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (_, _) => ListTile(
            leading: const Icon(Icons.cloud_off),
            title: const Text('Could not load this user.'),
            trailing: TextButton(
              onPressed: () => ref.invalidate(adminUserDetailProvider(uid)),
              child: const Text('Retry'),
            ),
          ),
          data: (d) => _Body(uid: uid, data: d),
        ),
      ],
    );
  }
}

class _Body extends ConsumerWidget {
  const _Body({required this.uid, required this.data});

  final String uid;
  final Map<String, dynamic> data;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = AdminUser.fromJson(_map(data['user']));
    final profile = _map(data['profile']);
    final theme = Theme.of(context);
    void refresh() => ref.invalidate(adminUserDetailProvider(uid));
    final sections = <Widget>[
      if (data['patient'] != null) ..._patient(context, _map(data['patient'])),
      if (data['doctor'] != null) ..._doctor(context, user, _map(data['doctor'])),
      if (data.containsKey('pharmacist'))
        const _Section(
          key: Key('section-pharmacist'),
          title: 'Prescription orders',
          child: Text(
            'Orders prepared, ready for collection and dispatched for delivery appear here '
            'once medication ordering (Module 13) is live.',
          ),
        ),
      _Section(
        key: const Key('section-activity'),
        title: 'Recent activity (30 days)',
        child: _list(data['activity']).isEmpty
            ? const Text('No recorded activity.')
            : Column(
                children: [
                  for (final e in _list(data['activity']))
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text(actionLabel('${e['action']}')),
                      subtitle: Text('${_when(e['timestamp'])} · ${e['details'] ?? ''}'),
                    ),
                ],
              ),
      ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Card(
          key: const Key('detail-header'),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Wrap(
              spacing: 24,
              runSpacing: 12,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                CircleAvatar(
                  radius: 28,
                  child: Text(user.name.isEmpty ? '?' : user.name[0].toUpperCase()),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(user.name, style: theme.textTheme.headlineSmall),
                    Text(user.email),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 8,
                      children: [
                        Chip(label: Text(roleLabel(user.role))),
                        Chip(
                          key: const Key('detail-status'),
                          label: Text(
                            user.isActive
                                ? 'Active'
                                : user.deletionRequested
                                ? 'Deletion pending'
                                : 'Deactivated',
                          ),
                          labelStyle: TextStyle(
                            color: user.isActive ? Colors.green.shade700 : Colors.red.shade700,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                _Facts({
                  'Joined': user.createdAt == null
                      ? '-'
                      : formatDate(user.createdAt!).split(',').first,
                  if (profile['icNumber'] != null) 'IC number': '${profile['icNumber']}',
                  if (profile['dateOfBirth'] != null) 'Date of birth': '${profile['dateOfBirth']}',
                  if (profile['gender'] != null) 'Gender': '${profile['gender']}',
                  if (profile['phone'] != null) 'Phone': '${profile['phone']}',
                  if (profile['onboardingComplete'] != null)
                    'Health profile': profile['onboardingComplete'] == true
                        ? 'Complete'
                        : 'Not completed yet',
                  if (user.isDoctor) 'Specialty': user.specialty ?? '-',
                  if (user.isDoctor)
                    'Caseload': '${user.caseload ?? 0} / ${user.maxPatients ?? 30} patients',
                }),
                Wrap(
                  spacing: 8,
                  children: [
                    OutlinedButton.icon(
                      key: const Key('detail-edit'),
                      onPressed: () async {
                        if (await editUser(context, ref, user)) refresh();
                      },
                      icon: const Icon(Icons.edit_outlined),
                      label: const Text('Edit'),
                    ),
                    OutlinedButton.icon(
                      key: const Key('detail-toggle'),
                      onPressed: () async {
                        if (await toggleUserActive(context, ref, user)) refresh();
                      },
                      icon: Icon(user.isActive ? Icons.block : Icons.check_circle_outline),
                      label: Text(user.isActive ? 'Deactivate' : 'Reactivate'),
                    ),
                    OutlinedButton.icon(
                      key: const Key('detail-delete'),
                      style: OutlinedButton.styleFrom(foregroundColor: theme.colorScheme.error),
                      onPressed: () async {
                        if (await deleteUser(context, ref, user) && context.mounted) {
                          context.go('/admin/users');
                        }
                      },
                      icon: const Icon(Icons.delete_outline),
                      label: const Text('Delete'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Wrap(spacing: 16, runSpacing: 16, children: sections),
      ],
    );
  }

  List<Widget> _patient(BuildContext context, Map<String, dynamic> p) {
    final doctor = p['doctor'] == null ? null : _map(p['doctor']);
    final reading = p['latestReading'] == null ? null : _map(p['latestReading']);
    final risk = p['risk'] == null ? null : _map(p['risk']);
    final level = _level(risk?['level']);
    final records = _map(p['records']);
    return [
      _Section(
        key: const Key('section-health'),
        title: 'Health overview',
        child: _Facts({
          'Assigned doctor': doctor == null ? 'Not assigned yet' : '${doctor['name']}',
          'Latest reading': reading == null
              ? 'No readings yet'
              : '${reading['systolic']}/${reading['diastolic']} mmHg · ${_when(reading['timestamp'])}',
          'Readings (30 days)': '${p['readingsLast30Days'] ?? 0}',
          'Risk level': level == null ? 'Not assessed yet' : _levelName(level),
          'Records': '${records['total'] ?? 0} uploaded · ${records['shared'] ?? 0} shared',
          'Family members': _list(p['family']).isEmpty
              ? 'None linked'
              : _list(p['family']).map((f) => f['name']).join(', '),
        }, highlight: level == null ? null : riskColor(level)),
      ),
      _Section(
        key: const Key('section-meds'),
        title: 'Medications',
        child: _list(p['medications']).isEmpty
            ? const Text('No medications recorded.')
            : Column(
                children: [
                  for (final m in _list(p['medications']))
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text('${m['name']} ${m['dosage'] ?? ''}'),
                      trailing: Text(
                        m['adherenceRate'] == null
                            ? '-'
                            : 'Adherence ${(m['adherenceRate'] as num).round()}%',
                      ),
                    ),
                ],
              ),
      ),
      _Section(
        key: const Key('section-appointments'),
        title: 'Appointments',
        child: _Appointments(rows: _list(p['appointments']), otherLabel: 'with'),
      ),
    ];
  }

  List<Widget> _doctor(BuildContext context, AdminUser user, Map<String, dynamic> d) => [
    _Section(
      key: const Key('section-patients'),
      title: 'Assigned patients (${_list(d['patients']).length})',
      child: _list(d['patients']).isEmpty
          ? const Text('No patients assigned.')
          : Column(
              children: [
                for (final p in _list(d['patients']))
                  ListTile(
                    key: Key('doctor-patient-${p['uid']}'),
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                      Icons.circle,
                      size: 12,
                      color: _level(p['riskLevel']) == null
                          ? Colors.grey
                          : riskColor(_level(p['riskLevel'])!),
                    ),
                    title: Text('${p['name']}${p['isActive'] == false ? ' (deactivated)' : ''}'),
                    subtitle: Text(
                      _level(p['riskLevel']) == null
                          ? 'Not assessed'
                          : '${_levelName(_level(p['riskLevel'])!)} risk',
                    ),
                    onTap: () => context.push('/admin/users/${p['uid']}'),
                  ),
              ],
            ),
    ),
    _Section(
      key: const Key('section-upcoming'),
      title: 'Upcoming appointments',
      child: _Appointments(rows: _list(d['upcoming']), otherLabel: 'patient'),
    ),
    _Section(
      key: const Key('section-workload'),
      title: 'Workload',
      child: _Facts({
        'Completed visits': '${d['completedTotal'] ?? 0}',
        'Open clinical alerts': '${d['openAlerts'] ?? 0}',
      }),
    ),
  ];
}

class _Section extends StatelessWidget {
  const _Section({super.key, required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 460,
    child: Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            child,
          ],
        ),
      ),
    ),
  );
}

class _Facts extends StatelessWidget {
  const _Facts(this.facts, {this.highlight});

  final Map<String, String> facts;
  final Color? highlight;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: [
      for (final MapEntry(key: k, value: v) in facts.entries)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(width: 140, child: Text(k, style: Theme.of(context).textTheme.bodySmall)),
              Flexible(
                child: Text(
                  v,
                  style: k == 'Risk level' && highlight != null
                      ? TextStyle(color: highlight, fontWeight: FontWeight.w600)
                      : null,
                ),
              ),
            ],
          ),
        ),
    ],
  );
}

class _Appointments extends StatelessWidget {
  const _Appointments({required this.rows, required this.otherLabel});

  final List<Map<String, dynamic>> rows;

  /// "with" (patient page: the doctor) or "patient" (doctor page).
  final String otherLabel;

  @override
  Widget build(BuildContext context) => rows.isEmpty
      ? const Text('No appointments.')
      : Column(
          children: [
            for (final a in rows)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text(_when(a['dateTime'])),
                subtitle: Text(
                  [
                    otherLabel == 'with' ? 'with ${a['other']}' : '${a['other']}',
                    AppointmentType.fromValue('${a['type'] ?? 'checkup'}').label,
                    '${a['status']}'.replaceAll('_', '-'),
                    if (a['bookedBy'] == 'admin') 'Admin assigned',
                    if (a['changeReason'] != null) '${a['changeReason']}',
                  ].join(' · '),
                ),
              ),
          ],
        );
}
