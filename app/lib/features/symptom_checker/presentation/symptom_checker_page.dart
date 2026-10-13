import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/enums.dart';
import '../../../core/utils/bp_classifier.dart';
import '../../../shared/services/api/api_client.dart';
import '../../dashboard/state/dashboard_providers.dart';
import '../../vitals/presentation/heart_rate_card.dart';
import '../../vitals/state/vitals_providers.dart';
import '../state/symptom_providers.dart';

/// Fig 4.3.8.1 Symptom Selection (FR-14.3; UC14.1, UC14.2 and E1; D-36).
///
/// Step 1 "Your vitals now": camera heart rate (mandatory step, skippable on poor
/// signal) and an optional BP the patient just measured. Step 2: symptoms + severity.
/// D-36: same window the server uses for "current BP" (backend services/triage.py).
const recentBpWindow = Duration(hours: 24);

class SymptomCheckerPage extends ConsumerStatefulWidget {
  const SymptomCheckerPage({super.key});

  /// Plain-language meaning of each severity level, shown under the choice.
  static const severityHints = {
    TriageSeverity.mild: 'Mild: noticeable, but not stopping your usual activities.',
    TriageSeverity.moderate: 'Moderate: bothering you and making some activities harder.',
    TriageSeverity.severe: 'Severe: very strong, or stopping you from doing normal activities.',
  };

  /// "today, 9:12 AM" / "yesterday, 8:05 PM" for the Vitals reading being reused.
  static String readingTime(DateTime t, DateTime now) {
    final day = DateTime(t.year, t.month, t.day);
    final today = DateTime(now.year, now.month, now.day);
    final h = t.hour % 12 == 0 ? 12 : t.hour % 12;
    final clock = '$h:${t.minute.toString().padLeft(2, '0')} ${t.hour < 12 ? 'AM' : 'PM'}';
    final label = day == today
        ? 'today'
        : day == today.subtract(const Duration(days: 1))
        ? 'yesterday'
        : '${t.day}/${t.month}';
    return '$label, $clock';
  }

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
  // The patient chose to type a newer BP instead of the one from Vitals.
  bool _enterNew = false;
  // A reading saved by an earlier attempt, reused on retry so it is not logged twice.
  String? _savedReadingId;
  String? _error;

  @override
  void dispose() {
    _sys.dispose();
    _dia.dispose();
    super.dispose();
  }

  /// Returns null when valid. Both BP fields empty = skipped (allowed).
  String? _bpProblem() {
    final s = _sys.text.trim(), d = _dia.text.trim();
    if (s.isEmpty && d.isEmpty) return null;
    final sys = int.tryParse(s), dia = int.tryParse(d);
    if (sys == null || dia == null) return 'Enter both numbers, or leave both empty.';
    return BpClassifier.plausibilityError(sys, dia);
  }

  void _toSymptoms() {
    final problem = _bpProblem();
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
      if (readingId == null && _sys.text.trim().isNotEmpty) {
        // D-36: a BP entered here is a normal reading (risk score, alerts) linked to triage.
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
            heartRate: _heartRate,
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

  Widget _vitalsStep(BuildContext context) {
    final now = ref.watch(nowProvider)();
    final latest = ref.watch(recentReadingsProvider).value?.firstOrNull;
    final recent = latest != null && now.difference(latest.timestamp) <= recentBpWindow
        ? latest
        : null;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('Step 1 of 2', style: Theme.of(context).textTheme.labelMedium),
        const SizedBox(height: 4),
        Text(
          'First, let\'s check your heart rate with the camera. It helps us give better '
          'advice. If it doesn\'t work, you can skip it.',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 12),
        HeartRateCard(onChanged: (bpm) => setState(() => _heartRate = bpm)),
        const SizedBox(height: 16),
        Text('Blood pressure', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 4),
        // D-36: the server uses the latest reading from the last 24 h unless a new one is
        // entered here; say so, so the patient is not asked for the same BP twice.
        if (recent != null && !_enterNew) ...[
          Card(
            key: const Key('sc-bp-from-vitals'),
            child: ListTile(
              leading: const Icon(Icons.monitor_heart_outlined),
              title: Text('${recent.systolic}/${recent.diastolic} mmHg'),
              subtitle: Text(
                'The blood pressure you logged in Vitals '
                '${SymptomCheckerPage.readingTime(recent.timestamp, now)} will be used for '
                'this check.',
              ),
            ),
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              key: const Key('sc-enter-newer'),
              onPressed: () => setState(() => _enterNew = true),
              child: const Text('I have a newer reading'),
            ),
          ),
        ] else ...[
          Text(
            recent == null
                ? 'No blood pressure logged in Vitals in the last 24 hours. If you have just '
                      'measured it, enter it here (it will be saved to Vitals). Otherwise you can '
                      'continue without it.'
                : 'Enter the reading you have just measured. It will be saved to Vitals and '
                      'used for this check.',
            key: const Key('sc-bp-hint'),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  key: const Key('sc-sys'),
                  onChanged: (_) => _savedReadingId = null, // edited: save the new values
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
                  onChanged: (_) => _savedReadingId = null, // edited: save the new values
                  controller: _dia,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(labelText: 'Diastolic', suffixText: 'mmHg'),
                ),
              ),
            ],
          ),
          if (recent != null)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                key: const Key('sc-use-earlier'),
                onPressed: () => setState(() {
                  _enterNew = false;
                  _sys.clear();
                  _dia.clear();
                  _error = null;
                  _savedReadingId = null;
                }),
                child: const Text('Use my earlier reading instead'),
              ),
            ),
        ],
        if (_error != null) ...[
          const SizedBox(height: 8),
          Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
        ],
        const SizedBox(height: 24),
        FilledButton(
          key: const Key('sc-next'),
          onPressed: _toSymptoms,
          child: Text(_heartRate == null ? 'Skip heart rate and continue' : 'Continue'),
        ),
      ],
    );
  }

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
