import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../shared/models/health_models.dart';
import '../../../shared/services/api/api_client.dart';
import '../domain/appointment_text.dart';
import '../../dashboard/state/dashboard_providers.dart';
import '../state/appointment_providers.dart';
import 'pre_visit_summary_page.dart';

/// Doctor (calendar) or admin (overview) opens an appointment: its pending request
/// (D-55: approve / decline), cancel with a reason, and the pre-visit summary (UC7.5).
void showAppointmentDetails(
  BuildContext context,
  Appointment a, {
  String? patientName,
  String? doctorName,
  bool forAdmin = false,
}) => showDialog<void>(
  context: context,
  builder: (_) => _DetailsDialog(
    appointment: a,
    patientName: patientName,
    doctorName: doctorName,
    forAdmin: forAdmin,
  ),
);

class _DetailsDialog extends ConsumerStatefulWidget {
  const _DetailsDialog({
    required this.appointment,
    this.patientName,
    this.doctorName,
    required this.forAdmin,
  });

  final Appointment appointment;
  final String? patientName;
  final String? doctorName;
  final bool forAdmin;

  @override
  ConsumerState<_DetailsDialog> createState() => _DetailsDialogState();
}

class _DetailsDialogState extends ConsumerState<_DetailsDialog> {
  bool _busy = false;

  Future<void> _run(Future<void> Function() action, String done) async {
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    final nav = Navigator.of(context);
    try {
      await action();
      nav.pop();
      messenger.showSnackBar(SnackBar(content: Text(done)));
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      messenger.showSnackBar(const SnackBar(content: Text('Something went wrong. Try again.')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<String?> _ask(String title, String label, {bool required = false}) {
    final text = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setState) => AlertDialog(
          title: Text(title),
          content: TextField(
            key: const Key('staff-note'),
            controller: text,
            maxLength: 300,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(labelText: label),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(c).pop(), child: const Text('Back')),
            FilledButton(
              key: const Key('staff-note-confirm'),
              onPressed: required && text.text.trim().length < 3
                  ? null
                  : () => Navigator.of(c).pop(text.text.trim()),
              child: const Text('Confirm'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final a = widget.appointment;
    final repo = ref.read(appointmentsRepositoryProvider);
    final p = a.pendingChange;
    final active = a.isActive;
    final now = ref.watch(nowProvider)();
    return AlertDialog(
      key: const Key('appointment-details'),
      title: Text('${widget.patientName ?? 'Patient'} · ${a.type.label}'),
      content: SizedBox(
        width: 560,
        height: 520,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${dateLabel(a.dateTime)}, ${timeLabel(a.dateTime)} · ${a.status.label}'
              '${widget.doctorName == null ? '' : ' · ${widget.doctorName}'}',
            ),
            if (a.isCancelled)
              Text(
                'Cancelled${a.cancelledBy == null ? '' : ' by ${a.cancelledBy}'}'
                '${a.changeReason == null ? '' : ': ${a.changeReason}'}',
                key: const Key('details-cancel-reason'),
              ),
            if (a.canRecordOutcome(now))
              Card(
                key: const Key('details-outcome'),
                color: a.isOverdue(now) ? Colors.red.withValues(alpha: 0.12) : null,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        a.isOverdue(now)
                            ? 'Not completed yet: record how the visit went.'
                            : 'The appointment has started.',
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        children: [
                          FilledButton.icon(
                            key: const Key('details-complete'),
                            icon: const Icon(Icons.check),
                            onPressed: _busy
                                ? null
                                : () => _run(
                                    () => repo.recordOutcome(a.id, completed: true),
                                    'Appointment completed.',
                                  ),
                            label: const Text('Complete appointment'),
                          ),
                          OutlinedButton(
                            key: const Key('details-no-show'),
                            onPressed: _busy
                                ? null
                                : () => _run(
                                    () => repo.recordOutcome(a.id, completed: false),
                                    'Marked as no-show.',
                                  ),
                            child: const Text('No-show'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            if (p != null && active)
              Card(
                key: const Key('details-pending'),
                color: Colors.amber.withValues(alpha: 0.2),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        p.isCancel
                            ? 'Patient asks to cancel'
                            : 'Patient asks to move to ${whenLabel(p.dateTime!, now)}',
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      Text('Reason: ${p.reasonText}'),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        children: [
                          FilledButton(
                            key: const Key('details-approve'),
                            onPressed: _busy
                                ? null
                                : () => _run(
                                    () => repo.decide(a.id, approve: true),
                                    'Request approved.',
                                  ),
                            child: const Text('Approve'),
                          ),
                          OutlinedButton(
                            key: const Key('details-decline'),
                            onPressed: _busy
                                ? null
                                : () async {
                                    final note = await _ask(
                                      'Decline request',
                                      'Message to the patient (optional)',
                                    );
                                    if (note == null) return;
                                    await _run(
                                      () => repo.decide(a.id, approve: false, note: note),
                                      'Request declined.',
                                    );
                                  },
                            child: const Text('Decline'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            const Divider(),
            Expanded(child: PreVisitSummaryView(appointmentId: a.id)),
          ],
        ),
      ),
      actions: [
        if (active)
          TextButton(
            key: const Key('details-cancel'),
            style: TextButton.styleFrom(foregroundColor: Theme.of(context).colorScheme.error),
            onPressed: _busy
                ? null
                : () async {
                    final reason = await _ask(
                      'Cancel appointment',
                      'Reason (sent to the patient)',
                      required: true,
                    );
                    if (reason == null || reason.isEmpty) return;
                    await _run(() => repo.staffCancel(a.id, reason), 'Appointment cancelled.');
                  },
            child: const Text('Cancel appointment'),
          ),
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Close')),
        if (!widget.forAdmin)
          FilledButton(
            onPressed: () {
              Navigator.of(context).pop();
              context.go('/doctor/patient/${a.patientId}');
            },
            child: const Text('Open patient'),
          ),
      ],
    );
  }
}
