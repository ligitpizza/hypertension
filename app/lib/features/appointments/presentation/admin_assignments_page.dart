import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/enums.dart';
import '../../../shared/services/api/api_client.dart';
import '../../admin/presentation/team_availability.dart';
import '../data/appointments_repository.dart';
import '../domain/appointment_text.dart';
import '../state/appointment_providers.dart';

/// Admin: Patient Assignments (Fig 4.3.14.2; FR-7.2, FR-11.2, UC7.3, UC11.2; D-54, D-59):
/// requests on the left, each doctor's caseload against their limit on the right.
class AdminAssignmentsPage extends ConsumerWidget {
  const AdminAssignmentsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final header = [
      Text('Patient assignments', style: Theme.of(context).textTheme.headlineSmall),
      const SizedBox(height: 4),
      const Text(
        'New patients asking for a doctor, and doctors asking to hand a patient over. '
        'Check each doctor\'s caseload before assigning.',
      ),
      const SizedBox(height: 16),
    ];
    return LayoutBuilder(
      builder: (context, box) {
        const requests = _Requests();
        const team = TeamAvailability();
        if (box.maxWidth < 900) {
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [...header, requests, const SizedBox(height: 24), team],
          );
        }
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            ...header,
            const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: requests),
                SizedBox(width: 24),
                Expanded(child: team),
              ],
            ),
          ],
        );
      },
    );
  }
}

class _Requests extends ConsumerWidget {
  const _Requests();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final requests = ref.watch(pendingAssignmentRequestsProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Doctor assignment requests', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        requests.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, _) => const Text('Could not load requests.'),
          data: (list) => list.isEmpty
              ? const Card(
                  key: Key('no-requests'),
                  child: ListTile(
                    leading: Icon(Icons.check_circle_outline),
                    title: Text('No pending requests.'),
                  ),
                )
              : Column(children: [for (final r in list) _RequestCard(request: r)]),
        ),
      ],
    );
  }
}

class _RequestCard extends ConsumerWidget {
  const _RequestCard({required this.request});

  final AssignmentRequest request;

  String _name(WidgetRef ref, String? uid) =>
      uid == null ? '-' : ref.watch(personProvider(uid)).value?.name ?? '…';

  Future<void> _approve(BuildContext context, WidgetRef ref) async {
    final doctor = await showDialog<String>(
      context: context,
      builder: (_) => _ChooseDoctor(
        initial: request.proposedDoctorId,
        exclude: request.kind == AssignmentRequestKind.reassign ? request.requestedBy : null,
      ),
    );
    if (doctor == null || !context.mounted) return;
    await _run(
      context,
      () => ref.read(appointmentsRepositoryProvider).approve(request.id, doctor),
      'Doctor assigned.',
    );
  }

  Future<void> _decline(BuildContext context, WidgetRef ref) async {
    final reason = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Decline request?'),
        content: TextField(
          key: const Key('decline-reason'),
          controller: reason,
          decoration: const InputDecoration(labelText: 'Message to the requester (optional)'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(c).pop(false), child: const Text('Back')),
          FilledButton(
            key: const Key('decline-confirm'),
            onPressed: () => Navigator.of(c).pop(true),
            child: const Text('Decline'),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    await _run(
      context,
      () => ref.read(appointmentsRepositoryProvider).decline(request.id, reason: reason.text),
      'Request declined.',
    );
  }

  Future<void> _run(BuildContext context, Future<void> Function() action, String done) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await action();
      messenger.showSnackBar(SnackBar(content: Text(done)));
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      messenger.showSnackBar(const SnackBar(content: Text('Something went wrong. Try again.')));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final r = request;
    final isNew = r.kind == AssignmentRequestKind.newPatient;
    return Card(
      key: Key('request-${r.id}'),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              isNew ? 'New patient needs a doctor' : 'Reassignment requested',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text('Patient: ${_name(ref, r.patientId)}'),
            if (!isNew) Text('Requested by: ${_name(ref, r.requestedBy)}'),
            if (r.proposedDoctorId != null)
              Text('Suggested doctor: ${_name(ref, r.proposedDoctorId)}'),
            if (r.reason != null && r.reason!.isNotEmpty) Text('Reason: ${r.reason}'),
            Text(
              'Sent ${dateLabel(r.createdAt)}, ${timeLabel(r.createdAt)}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                FilledButton(
                  key: Key('approve-${r.id}'),
                  onPressed: () => _approve(context, ref),
                  child: const Text('Assign doctor'),
                ),
                OutlinedButton(
                  key: Key('decline-${r.id}'),
                  onPressed: () => _decline(context, ref),
                  child: const Text('Decline'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ChooseDoctor extends ConsumerStatefulWidget {
  const _ChooseDoctor({this.initial, this.exclude});

  final String? initial;
  final String? exclude;

  @override
  ConsumerState<_ChooseDoctor> createState() => _ChooseDoctorState();
}

class _ChooseDoctorState extends ConsumerState<_ChooseDoctor> {
  late String? _doctor = widget.initial;

  @override
  Widget build(BuildContext context) {
    final doctors = [
      for (final d in ref.watch(doctorsProvider).value ?? const <PersonName>[])
        if (d.uid != widget.exclude) d,
    ];
    // D-59: show each doctor's caseload; warn before assigning to a full one.
    final loads = ref.watch(doctorCaseloadsProvider).value ?? const {};
    final chosen = loads[_doctor];
    final full = chosen != null && chosen.capacity == Capacity.full;
    return AlertDialog(
      key: const Key('choose-doctor'),
      title: const Text('Assign a doctor'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DropdownButtonFormField<String>(
            key: const Key('choose-doctor-field'),
            initialValue: doctors.any((d) => d.uid == _doctor) ? _doctor : null,
            decoration: const InputDecoration(labelText: 'Doctor'),
            items: [
              for (final d in doctors)
                DropdownMenuItem(
                  value: d.uid,
                  child: Text(
                    loads[d.uid] == null
                        ? d.name
                        : '${d.name} · ${loads[d.uid]!.caseload ?? 0}/'
                              '${loads[d.uid]!.maxPatients ?? 30}',
                  ),
                ),
            ],
            onChanged: (v) => setState(() => _doctor = v),
          ),
          if (full)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                '${chosen.name} is at capacity (${chosen.caseload}/${chosen.maxPatients}).',
                key: const Key('doctor-full'),
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
        FilledButton(
          key: const Key('choose-doctor-confirm'),
          onPressed: _doctor == null ? null : () => Navigator.of(context).pop(_doctor),
          child: Text(full ? 'Assign anyway' : 'Assign'),
        ),
      ],
    );
  }
}
