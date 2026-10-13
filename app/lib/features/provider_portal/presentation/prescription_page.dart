import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../shared/services/api/api_client.dart';
import '../domain/portal_models.dart';
import '../state/portal_providers.dart';
import 'portal_widgets.dart';

const frequencies = [
  'Once daily',
  'Once daily, morning',
  'Once daily, evening',
  'Twice daily',
  'Three times daily',
  'As needed',
];

/// Fig 4.3.12.7 Prescription Management (FR-8.3; UC8.4 and E1 interaction warning).
class PrescriptionPage extends ConsumerStatefulWidget {
  const PrescriptionPage({super.key, required this.patientId});

  final String patientId;

  @override
  ConsumerState<PrescriptionPage> createState() => _PrescriptionPageState();
}

class _PrescriptionPageState extends ConsumerState<PrescriptionPage> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _dosage = TextEditingController();
  final _duration = TextEditingController();
  String? _frequency;
  bool _recurring = false;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    for (final c in [_name, _dosage, _duration]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _submit({bool acknowledge = false}) async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final details = await ref
          .read(portalRepositoryProvider)
          .issuePrescription(
            widget.patientId,
            medicationName: _name.text.trim(),
            dosage: _dosage.text.trim(),
            frequency: _frequency!,
            duration: _duration.text,
            isRecurring: _recurring,
            acknowledgeInteractions: acknowledge,
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(key: const Key('rx-saved'), content: Text('Prescription issued: $details')),
      );
      _form.currentState!.reset();
      for (final c in [_name, _dosage, _duration]) {
        c.clear();
      }
      setState(() {
        _frequency = null;
        _recurring = false;
      });
    } on ApiException catch (e) {
      if (e.code == 'DRUG_INTERACTION') {
        setState(() => _saving = false);
        final proceed = await _confirmInteractions(InteractionWarning.fromDetails(e.details));
        if (proceed == true) return _submit(acknowledge: true);
        return;
      }
      setState(
        () => _error = e.code == 'NETWORK_ERROR' ? 'Could not reach the server.' : e.message,
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// UC8.4 E1: warn before saving; critical interactions need an explicit tick.
  Future<bool?> _confirmInteractions(List<InteractionWarning> warnings) {
    final critical = warnings.any((w) => w.isCritical);
    var reviewed = !critical;
    return showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialog) => AlertDialog(
          key: const Key('interaction-dialog'),
          icon: Icon(
            Icons.warning_amber_rounded,
            color: critical ? Theme.of(context).colorScheme.error : null,
          ),
          title: Text(critical ? 'Critical drug interaction' : 'Drug interaction'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final w in warnings)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text('With ${w.existingDrug} (${w.severity})'),
                    subtitle: Text(w.message),
                  ),
                if (critical)
                  CheckboxListTile(
                    key: const Key('interaction-reviewed'),
                    contentPadding: EdgeInsets.zero,
                    value: reviewed,
                    onChanged: (v) => setDialog(() => reviewed = v ?? false),
                    title: const Text(
                      'I have reviewed this interaction and still want to prescribe.',
                    ),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
            FilledButton(
              key: const Key('interaction-proceed'),
              onPressed: reviewed ? () => Navigator.pop(context, true) : null,
              child: const Text('Prescribe anyway'),
            ),
          ],
        ),
      ),
    );
  }

  String? _required(String? v) => (v == null || v.trim().isEmpty) ? 'Required' : null;

  @override
  Widget build(BuildContext context) {
    final id = widget.patientId;
    final patient = ref.watch(portalPatientProvider(id)).value;
    final meds = ref.watch(patientMedicationsProvider(id));
    final rx = ref.watch(patientPrescriptionsProvider(id));
    final notes = ref.watch(patientNotesProvider(id));
    final wide = MediaQuery.sizeOf(context).width >= 1000;

    final regimen = SectionCard(
      title: 'Current regimen',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AsyncSection(
            value: meds,
            isEmpty: (m) => m.isEmpty,
            emptyText: 'No medications on the patient\'s list.',
            builder: (m) => Column(
              children: [
                for (final x in m)
                  ListTile(
                    dense: true,
                    title: Text('${x.name} ${x.dosage}'),
                    subtitle: Text(x.schedule),
                  ),
              ],
            ),
          ),
          const Divider(),
          AsyncSection(
            value: rx,
            isEmpty: (p) => p.isEmpty,
            emptyText: 'No prescriptions issued yet.',
            builder: (p) => Column(
              children: [
                for (final x in p)
                  ListTile(
                    dense: true,
                    title: Text(x.medicationDetails),
                    subtitle: Text(
                      'Issued ${formatDate(x.issuedAt)}${x.isRecurring ? ' · recurring' : ''}',
                    ),
                  ),
              ],
            ),
          ),
          const Divider(),
          Text('Latest clinical note', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 4),
          Text(
            notes.value?.firstOrNull?.content ?? 'No clinical notes yet.',
            maxLines: 6,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontStyle: FontStyle.italic),
          ),
        ],
      ),
    );

    final form = SectionCard(
      title: 'New prescription',
      child: Form(
        key: _form,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextFormField(
              key: const Key('rx-name'),
              controller: _name,
              decoration: const InputDecoration(
                labelText: 'Medication name',
                hintText: 'e.g. Losartan',
              ),
              validator: _required,
            ),
            const SizedBox(height: 12),
            TextFormField(
              key: const Key('rx-dosage'),
              controller: _dosage,
              decoration: const InputDecoration(labelText: 'Dosage', hintText: 'e.g. 50mg'),
              validator: _required,
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              key: const Key('rx-frequency'),
              initialValue: _frequency,
              decoration: const InputDecoration(labelText: 'Frequency'),
              items: [for (final f in frequencies) DropdownMenuItem(value: f, child: Text(f))],
              onChanged: (v) => setState(() => _frequency = v),
              validator: (v) => v == null ? 'Required' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              key: const Key('rx-duration'),
              controller: _duration,
              decoration: const InputDecoration(
                labelText: 'Duration (optional)',
                hintText: 'e.g. 30 days',
              ),
            ),
            const SizedBox(height: 12),
            SwitchListTile(
              key: const Key('rx-recurring'),
              contentPadding: EdgeInsets.zero,
              value: _recurring,
              onChanged: (v) => setState(() => _recurring = v),
              title: const Text('Recurring for chronic condition'),
              subtitle: const Text('Monthly renewal orders start with the pharmacy module.'),
            ),
            if (_error != null)
              Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => context.go('/doctor/patient/$id'),
                  child: const Text('Cancel'),
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  key: const Key('rx-submit'),
                  onPressed: _saving ? null : _submit,
                  icon: const Icon(Icons.send),
                  label: Text(_saving ? 'Saving...' : 'Authorize'),
                ),
              ],
            ),
          ],
        ),
      ),
    );

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () => context.go('/doctor/patient/$id'),
            icon: const Icon(Icons.arrow_back),
            label: Text(patient?.name ?? 'Patient'),
          ),
        ),
        if (wide)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: regimen),
              const SizedBox(width: 16),
              Expanded(child: form),
            ],
          )
        else ...[
          form,
          const SizedBox(height: 16),
          regimen,
        ],
      ],
    );
  }
}
