import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../shared/services/api/api_client.dart';
import '../../medications/data/medications_repository.dart';
import '../../medications/state/medication_providers.dart';
import '../../provider_portal/domain/portal_models.dart';
import '../domain/prescription_text.dart';

/// D-50: the patient records (or edits) a prescription from another clinic.
class ReportedPrescriptionPage extends ConsumerStatefulWidget {
  const ReportedPrescriptionPage({super.key, this.existing});

  /// A patient-reported prescription being edited; null to record a new one.
  final Prescription? existing;

  @override
  ConsumerState<ReportedPrescriptionPage> createState() => _ReportedPrescriptionPageState();
}

class _ReportedPrescriptionPageState extends ConsumerState<ReportedPrescriptionPage> {
  final _form = GlobalKey<FormState>();
  late final PrescriptionParts? _parts = widget.existing == null
      ? null
      : parsePrescription(widget.existing!.medicationDetails);
  late final _name = TextEditingController(text: _parts?.name);
  late final _dosage = TextEditingController(text: _parts?.dosage);
  late final _duration = TextEditingController(text: _parts?.duration);
  late final _clinic = TextEditingController(text: _parts?.clinic);
  late String? _frequency = _parts?.frequency;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    for (final c in [_name, _dosage, _duration, _clinic]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _error = null);
    if (!_form.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      await ref
          .read(medicationsRepositoryProvider)
          .saveReportedPrescription(
            ReportedPrescription(
              medicationName: _name.text,
              dosage: _dosage.text,
              frequency: _frequency!,
              duration: _duration.text,
              clinic: _clinic.text,
            ),
            id: widget.existing?.id,
          );
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Prescription saved.')));
      context.pop();
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } catch (_) {
      setState(() => _error = 'Could not save. Please check your connection and try again.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Delete this prescription?'),
        content: const Text('It will be removed from your records and your doctor\'s view.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(c).pop(false), child: const Text('Cancel')),
          FilledButton(
            key: const Key('reported-delete-confirm'),
            onPressed: () => Navigator.of(c).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _saving = true);
    try {
      await ref.read(medicationsRepositoryProvider).deleteReportedPrescription(widget.existing!.id);
      if (mounted) context.pop();
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not delete. Please try again.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String? _required(String? v, String message) => (v ?? '').trim().isEmpty ? message : null;

  @override
  Widget build(BuildContext context) {
    final editing = widget.existing != null;
    return Scaffold(
      appBar: AppBar(
        title: Text(editing ? 'Edit prescription' : 'Record a prescription'),
        actions: [
          if (editing)
            IconButton(
              key: const Key('reported-delete'),
              tooltip: 'Delete',
              onPressed: _saving ? null : _delete,
              icon: const Icon(Icons.delete_outline),
            ),
        ],
      ),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              'For a prescription you received from another clinic or hospital. Your doctor '
              'will see it marked as reported by you.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            TextFormField(
              key: const Key('reported-name'),
              controller: _name,
              decoration: const InputDecoration(labelText: 'Medicine name'),
              textCapitalization: TextCapitalization.words,
              validator: (v) => (v ?? '').trim().length < 2 ? 'Enter the medicine name.' : null,
            ),
            TextFormField(
              key: const Key('reported-dosage'),
              controller: _dosage,
              decoration: const InputDecoration(labelText: 'Dosage', hintText: 'e.g. 500mg'),
              validator: (v) => _required(v, 'Enter the dosage.'),
            ),
            DropdownButtonFormField<String>(
              key: const Key('reported-frequency'),
              initialValue: _frequency,
              decoration: const InputDecoration(labelText: 'How often'),
              items: [for (final f in frequencies) DropdownMenuItem(value: f, child: Text(f))],
              onChanged: (v) => setState(() => _frequency = v),
              validator: (v) => v == null ? 'Choose how often.' : null,
            ),
            TextFormField(
              key: const Key('reported-duration'),
              controller: _duration,
              decoration: const InputDecoration(labelText: 'For how long (optional)'),
            ),
            TextFormField(
              key: const Key('reported-clinic'),
              controller: _clinic,
              decoration: const InputDecoration(
                labelText: 'Prescribed by / clinic (optional)',
                hintText: 'e.g. Klinik Kesihatan Setapak',
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ],
            const SizedBox(height: 24),
            FilledButton(
              key: const Key('reported-save'),
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox.square(dimension: 20, child: CircularProgressIndicator())
                  : const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }
}
