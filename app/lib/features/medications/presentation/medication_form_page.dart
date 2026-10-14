import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../shared/models/health_models.dart';
import '../../../shared/services/api/api_client.dart';
import '../data/medications_repository.dart';
import '../domain/med_schedule.dart';
import '../state/medication_providers.dart';

/// UC5.1 add / edit a medication, with UC5.1 E1 duplicate and UC5.6 interaction warnings.
class MedicationFormPage extends ConsumerStatefulWidget {
  const MedicationFormPage({super.key, this.existing});

  /// Null when adding.
  final Medication? existing;

  @override
  ConsumerState<MedicationFormPage> createState() => _MedicationFormPageState();
}

class _MedicationFormPageState extends ConsumerState<MedicationFormPage> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.existing?.name);
  late final _dosage = TextEditingController(text: widget.existing?.dosage);
  late final _quantity = TextEditingController(
    text: widget.existing?.quantityOnHand?.toStringAsFixed(0),
  );
  late final _threshold = TextEditingController(
    text: '${widget.existing?.refillThresholdDays ?? 7}',
  );
  late bool _asNeeded =
      widget.existing != null && tryParseSchedule(widget.existing!.schedule) == null;
  late final List<DoseTime> _times = [
    ...?(widget.existing == null ? null : tryParseSchedule(widget.existing!.schedule)),
  ];
  bool _saving = false;
  String? _error;

  bool get _editing => widget.existing != null;

  @override
  void dispose() {
    for (final c in [_name, _dosage, _quantity, _threshold]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _addTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: const TimeOfDay(hour: 8, minute: 0),
      helpText: 'Dose time (Malaysia time)',
    );
    if (picked == null) return;
    final t = DoseTime(picked.hour, picked.minute);
    setState(() {
      if (!_times.contains(t)) _times.add(t);
      _times.sort();
    });
  }

  MedicationDraft _draft() => MedicationDraft(
    name: _name.text.trim(),
    dosage: _dosage.text.trim(),
    schedule: formatSchedule(_asNeeded ? null : _times),
    quantityOnHand: double.tryParse(_quantity.text.trim()),
    refillThresholdDays: int.tryParse(_threshold.text.trim()) ?? 7,
  );

  Future<void> _save({bool acknowledge = false}) async {
    setState(() => _error = null);
    if (!_form.currentState!.validate()) return;
    if (!_asNeeded && _times.isEmpty) {
      setState(() => _error = 'Add at least one dose time, or choose "As needed".');
      return;
    }
    setState(() => _saving = true);
    try {
      await ref
          .read(medicationsRepositoryProvider)
          .save(_draft(), id: widget.existing?.id, acknowledge: acknowledge);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_editing ? 'Medication updated.' : 'Medication added.')),
      );
      context.pop();
    } on MedicationWarnings catch (w) {
      if (!mounted) return;
      setState(() => _saving = false);
      final go = await _showWarnings(context, w);
      if (go == true) await _save(acknowledge: true);
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
        title: const Text('Delete medication?'),
        content: Text('${widget.existing!.name} and its reminders will be removed.'),
        actions: [
          TextButton(onPressed: () => c.pop(false), child: const Text('Cancel')),
          FilledButton(onPressed: () => c.pop(true), child: const Text('Delete')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _saving = true);
    try {
      await ref.read(medicationsRepositoryProvider).delete(widget.existing!.id);
      if (mounted) context.pop();
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not delete. Please try again.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final digits = [FilteringTextInputFormatter.digitsOnly];
    return Scaffold(
      appBar: AppBar(
        title: Text(_editing ? 'Edit medication' : 'Add medication'),
        actions: [
          if (_editing)
            IconButton(
              key: const Key('delete-medication'),
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
            TextFormField(
              key: const Key('med-name'),
              controller: _name,
              decoration: const InputDecoration(labelText: 'Medicine name'),
              textCapitalization: TextCapitalization.words,
              validator: (v) => (v ?? '').trim().length < 2 ? 'Enter the medicine name.' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              key: const Key('med-dosage'),
              controller: _dosage,
              decoration: const InputDecoration(
                labelText: 'Dosage',
                hintText: 'e.g. 5mg, 1 tablet',
              ),
              validator: (v) => (v ?? '').trim().isEmpty ? 'Enter the dosage.' : null,
            ),
            const SizedBox(height: 16),
            Text('When do you take it?', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            SegmentedButton<bool>(
              key: const Key('med-mode'),
              segments: const [
                ButtonSegment(value: false, label: Text('At set times')),
                ButtonSegment(value: true, label: Text('As needed')),
              ],
              selected: {_asNeeded},
              onSelectionChanged: (s) => setState(() => _asNeeded = s.first),
            ),
            if (!_asNeeded) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final t in _times)
                    InputChip(
                      key: Key('time-${t.hhmm}'),
                      label: Text(t.label),
                      onDeleted: () => setState(() => _times.remove(t)),
                    ),
                  ActionChip(
                    key: const Key('add-time'),
                    avatar: const Icon(Icons.add_alarm, size: 18),
                    label: const Text('Add time'),
                    onPressed: _times.length >= 8 ? null : _addTime,
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                "You'll get a reminder at each time (Malaysia time).",
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            const SizedBox(height: 16),
            TextFormField(
              key: const Key('med-quantity'),
              controller: _quantity,
              keyboardType: TextInputType.number,
              inputFormatters: digits,
              decoration: const InputDecoration(
                labelText: 'Doses on hand (optional)',
                helperText: 'Used for refill reminders.',
              ),
            ),
            const SizedBox(height: 12),
            TextFormField(
              key: const Key('med-threshold'),
              controller: _threshold,
              keyboardType: TextInputType.number,
              inputFormatters: digits,
              decoration: const InputDecoration(
                labelText: 'Remind me to refill when this many days are left',
              ),
              validator: (v) {
                final n = int.tryParse((v ?? '').trim());
                return n == null || n < 1 || n > 60 ? 'Enter 1 to 60 days.' : null;
              },
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                _error!,
                key: const Key('med-error'),
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            const SizedBox(height: 24),
            FilledButton(
              key: const Key('save-medication'),
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

/// UC5.1 E1 / UC5.6 E1: show warnings; true = save anyway.
Future<bool?> _showWarnings(BuildContext context, MedicationWarnings w) => showDialog<bool>(
  context: context,
  builder: (c) => AlertDialog(
    key: const Key('med-warnings'),
    icon: const Icon(Icons.warning_amber_rounded),
    title: const Text('Please check before saving'),
    content: SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final d in w.duplicates)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text('You already have $d on your list.'),
            ),
          for (final i in w.interactions)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                '${i.isCritical ? 'Serious interaction' : 'Possible interaction'} '
                'with ${i.existingDrug} (${i.severity}): ${i.message}',
              ),
            ),
          const SizedBox(height: 4),
          Text(
            'This check is not a substitute for a doctor or pharmacist. '
            'Ask them before taking these together.',
            style: Theme.of(c).textTheme.bodySmall,
          ),
        ],
      ),
    ),
    actions: [
      TextButton(onPressed: () => c.pop(false), child: const Text('Go back')),
      FilledButton(
        key: const Key('save-anyway'),
        onPressed: () => c.pop(true),
        child: const Text('Save anyway'),
      ),
    ],
  ),
);
