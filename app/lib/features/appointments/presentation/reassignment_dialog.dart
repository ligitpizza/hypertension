import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/services/api/api_client.dart';
import '../../auth/state/auth_providers.dart';
import '../state/appointment_providers.dart';

/// D-54: the patient's doctor asks the admin to move the patient to another doctor.
Future<void> requestReassignment(BuildContext context, String patientId, String patientName) =>
    showDialog<void>(
      context: context,
      builder: (_) => _ReassignDialog(patientId: patientId, patientName: patientName),
    );

class _ReassignDialog extends ConsumerStatefulWidget {
  const _ReassignDialog({required this.patientId, required this.patientName});

  final String patientId;
  final String patientName;

  @override
  ConsumerState<_ReassignDialog> createState() => _ReassignDialogState();
}

class _ReassignDialogState extends ConsumerState<_ReassignDialog> {
  String? _doctor;
  final _reason = TextEditingController();
  bool _sending = false;
  String? _error;

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      await ref
          .read(appointmentsRepositoryProvider)
          .requestReassignment(widget.patientId, proposedDoctorId: _doctor, reason: _reason.text);
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      Navigator.of(context).pop();
      messenger.showSnackBar(const SnackBar(content: Text('Request sent to the admin.')));
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } catch (_) {
      setState(() => _error = 'Could not send the request. Please try again.');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final me = ref.watch(authUidProvider).value;
    final doctors = [
      for (final d in ref.watch(doctorsProvider).value ?? const [])
        if (d.uid != me) d,
    ];
    return AlertDialog(
      key: const Key('reassign-dialog'),
      title: Text('Reassign ${widget.patientName}'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('The admin will choose the new doctor and confirm the change.'),
            const SizedBox(height: 12),
            DropdownButtonFormField<String?>(
              key: const Key('reassign-doctor'),
              initialValue: _doctor,
              decoration: const InputDecoration(labelText: 'Suggested doctor (optional)'),
              items: [
                const DropdownMenuItem(value: null, child: Text('No preference')),
                for (final d in doctors) DropdownMenuItem(value: d.uid, child: Text(d.name)),
              ],
              onChanged: (v) => setState(() => _doctor = v),
            ),
            TextField(
              key: const Key('reassign-reason'),
              controller: _reason,
              maxLength: 500,
              decoration: const InputDecoration(labelText: 'Reason (optional)'),
            ),
            if (_error != null)
              Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
        FilledButton(
          key: const Key('reassign-send'),
          onPressed: _sending ? null : _send,
          child: const Text('Send request'),
        ),
      ],
    );
  }
}
