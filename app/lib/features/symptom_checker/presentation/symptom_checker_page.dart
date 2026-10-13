import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/enums.dart';
import '../../../core/utils/bp_classifier.dart';
import '../../../shared/services/api/api_client.dart';
import '../../vitals/presentation/heart_rate_card.dart';
import '../../vitals/state/vitals_providers.dart';
import '../state/symptom_providers.dart';

/// Fig 4.3.8.1 Symptom Selection (FR-14.3; UC14.1, UC14.2; D-38).
///
/// Step 1 "Your vitals now": heart rate (camera, or the pulse typed from the BP monitor)
/// and a fresh blood pressure are both compulsory (D-38); Call 999 stays available so the
/// step never blocks emergency help. Step 2: symptoms + severity.

class SymptomCheckerPage extends ConsumerStatefulWidget {
  const SymptomCheckerPage({super.key});

  /// Plain-language meaning of each severity level, shown under the choice.
  static const severityHints = {
    TriageSeverity.mild: 'Mild: noticeable, but not stopping your usual activities.',
    TriageSeverity.moderate: 'Moderate: bothering you and making some activities harder.',
    TriageSeverity.severe: 'Severe: very strong, or stopping you from doing normal activities.',
  };

  static const categoryLabels = {
    'common': 'Common symptoms',
    'warning_signs': 'Warning signs',
    'other': 'Other symptoms',
  };

  @override
  ConsumerState<SymptomCheckerPage> createState() => _SymptomCheckerPageState();
}

class _SymptomCheckerPageState extends ConsumerState<SymptomCheckerPage> {
  int _step = 0;
  int? _heartRate;
  final _sys = TextEditingController();
  final _dia = TextEditingController();
  final Set<String> _selected = {};
  TriageSeverity _severity = TriageSeverity.mild;
  bool _submitting = false;
  // A reading saved by an earlier attempt, reused on retry so it is not logged twice.
  String? _savedReadingId;
  String? _error;

  @override
  void dispose() {
    _sys.dispose();
    _dia.dispose();
    super.dispose();
  }

  /// D-38: a fresh BP is compulsory. Returns null when valid.
  String? _bpProblem() {
    final sys = int.tryParse(_sys.text.trim()), dia = int.tryParse(_dia.text.trim());
    if (sys == null || dia == null) return 'Enter both blood pressure numbers.';
    return BpClassifier.plausibilityError(sys, dia, heartRate: _heartRate);
  }

  bool get _vitalsComplete => _heartRate != null && _bpProblem() == null;

  void _toSymptoms() {
    final problem = _heartRate == null
        ? 'Measure your heart rate with the camera, or type your pulse from your monitor.'
        : _bpProblem();
    setState(() => _error = problem);
    if (problem == null) setState(() => _step = 1);
  }

  Future<void> _submit() async {
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      var readingId = _savedReadingId;
      if (readingId == null) {
        // D-38: the BP entered here is a normal reading (risk score, alerts) linked to triage.
        final saved = await ref
            .read(vitalsRepositoryProvider)
            .logReading(
              systolic: int.parse(_sys.text.trim()),
              diastolic: int.parse(_dia.text.trim()),
              heartRate: _heartRate,
              note: 'Symptom checker',
            );
        readingId = _savedReadingId = saved.id;
      }
      final result = await ref
          .read(symptomRepositoryProvider)
          .submit(
            symptomIds: _selected.toList(),
            severity: _severity,
            heartRate: _heartRate!,
            vitalReadingId: readingId,
          );
      if (mounted) context.pushReplacement('/symptom/result/${result.id}', extra: result);
    } on ApiException catch (e) {
      setState(
        () => _error = e.code == 'NETWORK_ERROR'
            ? 'Could not reach the server. Please try again. If you feel very unwell, call 999.'
            : e.message,
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: BackButton(
          onPressed: () => _step == 1
              ? setState(() => _step = 0)
              : (context.canPop() ? context.pop() : context.go('/dashboard')),
        ),
        title: Text(_step == 0 ? 'Your vitals now' : 'Symptom selection'),
      ),
      body: SafeArea(child: _step == 0 ? _vitalsStep(context) : _symptomStep(context)),
    );
  }

  Widget _vitalsStep(BuildContext context) => ListView(
    padding: const EdgeInsets.all(16),
    children: [
      Text('Step 1 of 2', style: Theme.of(context).textTheme.labelMedium),
      const SizedBox(height: 4),
      const Text(
        'Before checking your symptoms, we need your heart rate and blood pressure right now.',
      ),
      const SizedBox(height: 12),
      Text('Heart rate (required)', style: Theme.of(context).textTheme.titleMedium),
      const Text(
        'Measure it with the camera. If the camera cannot get a reading, type the pulse shown '
        'on your blood pressure monitor.',
      ),
      const SizedBox(height: 8),
      HeartRateCard(allowSkip: false, onChanged: (bpm) => setState(() => _heartRate = bpm)),
      const SizedBox(height: 16),
      Text('Blood pressure (required)', style: Theme.of(context).textTheme.titleMedium),
      const Text(
        'Measure your blood pressure now and enter it. It will be saved to Vitals.',
        key: Key('sc-bp-hint'),
      ),
      const SizedBox(height: 8),
      Row(
        children: [
          Expanded(
            child: TextField(
              key: const Key('sc-sys'),
              onChanged: (_) => setState(() => _savedReadingId = null), // new values: save them
              controller: _sys,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(labelText: 'Systolic', suffixText: 'mmHg'),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: TextField(
              key: const Key('sc-dia'),
              onChanged: (_) => setState(() => _savedReadingId = null),
              controller: _dia,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(labelText: 'Diastolic', suffixText: 'mmHg'),
            ),
          ),
        ],
      ),
      if (_error != null) ...[
        const SizedBox(height: 8),
        Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
      ],
      const SizedBox(height: 24),
      FilledButton(
        key: const Key('sc-next'),
        onPressed: _vitalsComplete ? _toSymptoms : null,
        child: const Text('Continue'),
      ),
      const SizedBox(height: 16),
      // D-38 safety exit: the compulsory step must never block emergency help.
      Card(
        key: const Key('sc-call-999-card'),
        child: ListTile(
          leading: Icon(Icons.call, color: BpClassifier.color(BpCategory.crisis)),
          title: const Text('Feeling very unwell or can\'t measure right now?'),
          subtitle: const Text('Call 999 for emergency help.'),
          trailing: FilledButton(
            key: const Key('sc-call-999'),
            style: FilledButton.styleFrom(backgroundColor: BpClassifier.color(BpCategory.crisis)),
            onPressed: () => ref.read(dialerProvider)('999'),
            child: const Text('Call 999'),
          ),
        ),
      ),
    ],
  );

  Widget _symptomStep(BuildContext context) {
    final catalog = ref.watch(symptomCatalogProvider);
    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text('Step 2 of 2', style: Theme.of(context).textTheme.labelMedium),
              Text('What are you feeling today?', style: Theme.of(context).textTheme.headlineSmall),
              const Text('Select all symptoms you are currently experiencing.'),
              const SizedBox(height: 12),
              catalog.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (_, _) => const Text(
                  'Could not load the symptom list. Check your connection and try again. '
                  'If you feel very unwell, call 999.',
                ),
                data: (list) => list.isEmpty
                    ? const Text(
                        'The symptom list is not available right now. Please try again later. '
                        'If you feel very unwell, call 999.',
                        key: Key('sc-empty'),
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          for (final cat in SymptomCheckerPage.categoryLabels.keys)
                            if (list.any((s) => s.category == cat)) ...[
                              const SizedBox(height: 8),
                              Text(
                                SymptomCheckerPage.categoryLabels[cat]!.toUpperCase(),
                                style: Theme.of(context).textTheme.labelMedium,
                              ),
                              const SizedBox(height: 8),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: [
                                  for (final s in list.where((s) => s.category == cat))
                                    FilterChip(
                                      key: Key('sym-${s.id}'),
                                      label: Text(s.name),
                                      selected: _selected.contains(s.id),
                                      onSelected: (on) => setState(
                                        () => on ? _selected.add(s.id) : _selected.remove(s.id),
                                      ),
                                    ),
                                ],
                              ),
                            ],
                        ],
                      ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('SEVERITY', style: Theme.of(context).textTheme.labelMedium),
              const SizedBox(height: 8),
              SegmentedButton<TriageSeverity>(
                key: const Key('sc-severity'),
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(value: TriageSeverity.mild, label: Text('Mild')),
                  ButtonSegment(value: TriageSeverity.moderate, label: Text('Moderate')),
                  ButtonSegment(value: TriageSeverity.severe, label: Text('Severe')),
                ],
                selected: {_severity},
                onSelectionChanged: (s) => setState(() => _severity = s.first),
              ),
              const SizedBox(height: 6),
              Text(
                SymptomCheckerPage.severityHints[_severity]!,
                key: const Key('sc-severity-hint'),
                style: Theme.of(context).textTheme.bodySmall,
              ),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
              ],
              const SizedBox(height: 12),
              FilledButton(
                key: const Key('sc-submit'),
                onPressed: _selected.isEmpty || _submitting ? null : _submit,
                child: Text(_submitting ? 'Checking...' : 'Continue'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
