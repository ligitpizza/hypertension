import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/enums.dart';
import '../../../core/theme/app_theme.dart';
import '../data/symptom_repository.dart';
import '../state/symptom_providers.dart';

/// Fig 4.3.8.2 Triage Result (FR-14.3; UC14.3, UC14.4). Emergency number is 999
/// (Malaysia; the mockup's 911 is not used).
class TriageResultPage extends ConsumerWidget {
  const TriageResultPage({super.key, required this.result});

  final TriageResult result;

  static const emergencyNumber = '999';

  static (String, String, Color, IconData) header(TriageOutcome o) => switch (o) {
    TriageOutcome.seekEmergencyCare => (
      'Seek Emergency Care',
      'Call 999 or go to the nearest emergency department now.',
      BpColors.crisis,
      Icons.emergency,
    ),
    TriageOutcome.contactDoctor => (
      'Contact Your Doctor',
      'Please contact your doctor today about these symptoms.',
      BpColors.elevated,
      Icons.medical_services_outlined,
    ),
    TriageOutcome.monitorAtHome => (
      'Monitor at Home',
      'Your symptoms can be looked after at home for now.',
      BpColors.normal,
      Icons.home_outlined,
    ),
  };

  /// Numbered immediate actions (Fig 4.3.8.2).
  static List<(String, String)> actions(TriageOutcome o) => switch (o) {
    TriageOutcome.seekEmergencyCare => const [
      ('Call 999', 'Tell the operator your symptoms and that you have high blood pressure.'),
      ('Unlock your door', 'If you are alone, unlock the door so help can reach you.'),
      ('Rest and wait', 'Sit or lie down and try to stay calm. Do not drive yourself.'),
    ],
    TriageOutcome.contactDoctor => const [
      ('Contact your doctor today', 'Your doctor has been notified. Call or book an appointment.'),
      (
        'Avoid physical exertion',
        'Rest while you wait for your doctor. Sit quietly for 5 minutes, then re-measure.',
      ),
      ('Watch for warning signs', 'Call 999 if you get chest pain, breathlessness or weakness.'),
    ],
    TriageOutcome.monitorAtHome => const [
      ('Rest', 'Sit quietly and drink some water.'),
      ('Keep logging', 'Measure your blood pressure again later today.'),
      ('Get help if it changes', 'Run the checker again, or call 999 if you feel much worse.'),
    ],
  };

  static const _missingLabels = {
    'heart_rate': 'heart rate',
    'recent_blood_pressure': 'a blood pressure reading from the last 24 hours',
    'risk_score': 'a risk assessment',
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final (title, subtitle, color, icon) = header(result.outcome);
    final emergency = result.outcome == TriageOutcome.seekEmergencyCare;
    final redFlags = result.symptoms.where((s) => s.isRedFlag).toList();
    final missing = [for (final m in result.missingInputs) ?_missingLabels[m]];
    final bp = result.systolic == null ? null : '${result.systolic}/${result.diastolic} mmHg';

    return Scaffold(
      appBar: AppBar(
        leading: BackButton(onPressed: () => context.go('/dashboard')),
        title: const Text('Triage result'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            key: Key('triage-${result.outcome.value}'),
            color: color,
            child: ListTile(
              leading: Icon(icon, color: Colors.white, size: 36),
              title: Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 20,
                ),
              ),
              subtitle: Text(subtitle, style: const TextStyle(color: Colors.white)),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    redFlags.isNotEmpty ? 'Critical symptoms reported' : 'Symptoms reported',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final s in result.symptoms)
                        Chip(
                          label: Text(s.name),
                          backgroundColor: s.isRedFlag
                              ? BpColors.crisis.withValues(alpha: 0.15)
                              : null,
                          avatar: s.isRedFlag
                              ? const Icon(
                                  Icons.warning_amber_rounded,
                                  color: BpColors.crisis,
                                  size: 18,
                                )
                              : null,
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(result.reason, key: const Key('triage-reason')),
                  const SizedBox(height: 8),
                  Text(
                    [
                      if (bp != null) 'Blood pressure $bp',
                      if (result.heartRate != null)
                        'heart rate ${result.heartRate} bpm (camera estimate)',
                    ].join(' · '),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  if (missing.isNotEmpty)
                    Text(
                      'Checked without ${missing.join(', ')}.',
                      key: const Key('triage-missing'),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text('Immediate actions', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          for (final (i, (heading, detail)) in actions(result.outcome).indexed)
            Card(
              child: ListTile(
                leading: CircleAvatar(child: Text('${i + 1}')),
                title: Text(heading),
                subtitle: Text(detail),
              ),
            ),
          const SizedBox(height: 12),
          if (emergency)
            FilledButton.icon(
              key: const Key('triage-call-999'),
              style: FilledButton.styleFrom(
                backgroundColor: BpColors.crisis,
                minimumSize: const Size.fromHeight(52),
              ),
              onPressed: () async {
                final opened = await ref.read(dialerProvider)(emergencyNumber);
                if (!opened && context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Could not open the dialer. Please dial 999.')),
                  );
                }
              },
              icon: const Icon(Icons.call),
              label: const Text('Call 999 Now'),
            ),
          if (result.doctorNotified)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'Your doctor has been notified.',
                key: const Key('triage-doctor-notified'),
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
          if (!emergency) ...[
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () => context.push('/ai-agent'),
              icon: const Icon(Icons.smart_toy_outlined),
              label: const Text('Ask the AI Health Agent'),
            ),
          ],
          const SizedBox(height: 16),
          Text(
            'This checker gives general guidance. It is not a substitute for a doctor. '
            'If you feel worse at any time, call 999.',
            key: const Key('triage-disclaimer'),
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}
