import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/utils/bp_classifier.dart';
import '../../../shared/services/api/api_client.dart';
import '../state/vitals_providers.dart';
import 'heart_rate_card.dart';

/// Fig 4.3.3.2 Log Vitals (FR-3.1, FR-3.2; UC3.1-UC3.3; Fig 4.1.1.3).
class LogVitalsPage extends ConsumerStatefulWidget {
  const LogVitalsPage({super.key});

  @override
  ConsumerState<LogVitalsPage> createState() => _LogVitalsPageState();
}

class _LogVitalsPageState extends ConsumerState<LogVitalsPage> {
  final _form = GlobalKey<FormState>();
  final _sys = TextEditingController();
  final _dia = TextEditingController();
  final _note = TextEditingController();
  int? _heartRate;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    for (final c in [_sys, _dia, _note]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _error = null);
    if (!_form.currentState!.validate()) return;
    final sys = int.parse(_sys.text);
    final dia = int.parse(_dia.text);
    // UC3.1 E1: same plausible range as the server; ask the patient to re-check.
    final problem = BpClassifier.plausibilityError(sys, dia, heartRate: _heartRate);
    if (problem != null) {
      setState(() => _error = '$problem Please re-check your monitor and try again.');
      return;
    }
    setState(() => _saving = true);
    try {
      final saved = await ref
          .read(vitalsRepositoryProvider)
          .logReading(systolic: sys, diastolic: dia, heartRate: _heartRate, note: _note.text);
      if (mounted) context.pushReplacement('/vitals/saved', extra: saved);
    } on ApiException catch (e) {
      if (mounted) {
        setState(
          () => _error = e.code == 'READING_OUT_OF_RANGE'
              ? '${e.message} Please re-check your monitor and try again.'
              : e.code == 'NETWORK_ERROR'
              ? 'Could not reach the server. Your reading was not saved; please try again.'
              : e.message,
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String? _requiredNumber(String? v, String label) =>
      (v == null || v.isEmpty) ? 'Enter your $label' : null;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Vitals Tracking')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text('Track Your Vitals'),
            const Text('Log your latest numbers or measure your heart rate right now.'),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: scheme.primaryContainer.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(16),
                border: Border(left: BorderSide(color: scheme.primary, width: 4)),
              ),
              child: Form(
                key: _form,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.favorite, color: scheme.primary),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Blood Pressure',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        ),
                        const Chip(label: Text('Manual Entry')),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: TextFormField(
                            key: const Key('bp-systolic'),
                            controller: _sys,
                            keyboardType: TextInputType.number,
                            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                            decoration: const InputDecoration(
                              labelText: 'Systolic (Top)',
                              hintText: '120',
                              suffixText: 'mmHg',
                            ),
                            validator: (v) => _requiredNumber(v, 'systolic (top) number'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextFormField(
                            key: const Key('bp-diastolic'),
                            controller: _dia,
                            keyboardType: TextInputType.number,
                            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                            decoration: const InputDecoration(
                              labelText: 'Diastolic (Bottom)',
                              hintText: '80',
                              suffixText: 'mmHg',
                            ),
                            validator: (v) => _requiredNumber(v, 'diastolic (bottom) number'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      key: const Key('bp-note'),
                      controller: _note,
                      maxLength: 500,
                      decoration: const InputDecoration(
                        labelText: 'Note (optional)',
                        hintText: 'e.g. after exercise',
                      ),
                    ),
                    if (_heartRate != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text(
                          'Heart rate $_heartRate bpm will be saved with this reading.',
                          key: const Key('bp-hr-attached'),
                        ),
                      ),
                    if (_error != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text(
                          _error!,
                          key: const Key('bp-error'),
                          style: TextStyle(color: scheme.error),
                        ),
                      ),
                    FilledButton.icon(
                      key: const Key('bp-save'),
                      onPressed: _saving ? null : _save,
                      icon: _saving
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.check),
                      label: const Text('Save Reading'),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            HeartRateCard(onChanged: (bpm) => setState(() => _heartRate = bpm)),
          ],
        ),
      ),
    );
  }
}
