import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/risk_style.dart';
import 'portal_widgets.dart' show formatDate;
import '../domain/portal_models.dart';
import '../state/portal_providers.dart';

/// D-44 "Since starting medication": BP and model risk before vs now, on the patient
/// detail Medications tab. Only blood pressure differs between the two model runs.
class MedicationEffectCard extends ConsumerWidget {
  const MedicationEffectCard({super.key, required this.patientId});

  final String patientId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final effect = ref.watch(medicationEffectProvider(patientId));
    final theme = Theme.of(context);
    return Card(
      key: const Key('medication-effect'),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Since starting medication', style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            effect.when(
              loading: () => const LinearProgressIndicator(),
              error: (_, _) => Row(
                children: [
                  const Expanded(child: Text('Could not load the comparison.')),
                  TextButton(
                    onPressed: () => ref.invalidate(medicationEffectProvider(patientId)),
                    child: const Text('Retry'),
                  ),
                ],
              ),
              data: (e) => _Body(effect: e),
            ),
          ],
        ),
      ),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({required this.effect});

  final MedicationEffect effect;

  @override
  Widget build(BuildContext context) {
    final e = effect;
    final started = e.startedAt == null
        ? ''
        : '${e.firstMedication} added ${formatDate(e.startedAt!)} (${e.daysOnMedication} days ago). ';
    final small = Theme.of(context).textTheme.bodySmall;
    switch (e.status) {
      case 'no_medication':
        return const Text('The patient has not added any medications yet.');
      case 'no_baseline':
        return Text('${started}There are no readings from before that date to compare with.');
      case 'no_followup':
        return Text('${started}No readings have been logged since then.');
    }
    final (sb, db) = e.bpBefore!;
    final (sa, da) = e.bpAfter!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(started),
        const SizedBox(height: 8),
        Text(
          'Average BP: ${sb.round()}/${db.round()} → ${sa.round()}/${da.round()} mmHg',
          key: const Key('effect-bp'),
          style: Theme.of(context).textTheme.titleMedium,
        ),
        Text(
          'Before: last ${e.readingsBefore} reading(s) before the first medicine. '
          'Now: latest ${e.readingsAfter} reading(s).',
          style: small,
        ),
        if (e.early)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              'Early days: most BP medicines take 2–4 weeks to reach full effect.',
              key: const Key('effect-early'),
              style: small?.copyWith(fontWeight: FontWeight.bold),
            ),
          ),
        if (e.status == 'model_unavailable')
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: Text('Risk models are unavailable right now; showing BP only.'),
          )
        else ...[
          const SizedBox(height: 8),
          for (final MapEntry(key: c, value: (before, after)) in e.complications.entries)
            _RiskRow(name: factorLabel(c), before: before, after: after),
          const SizedBox(height: 8),
          Text(
            'Model estimate on the same patient profile; only blood pressure differs. The '
            'medication input is held fixed because in the training data people on BP '
            'medicine were sicker on average. Not proof that the medicine caused the change.',
            style: small,
          ),
        ],
      ],
    );
  }
}

class _RiskRow extends StatelessWidget {
  const _RiskRow({required this.name, required this.before, required this.after});

  final String name;
  final double before;
  final double after;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final diff = after - before;
    // Under half a percentage point is shown as unchanged.
    final (icon, color) = diff <= -0.5
        ? (Icons.arrow_downward, Colors.green.shade700)
        : diff >= 0.5
        ? (Icons.arrow_upward, scheme.error)
        : (Icons.remove, scheme.outline);
    return Padding(
      key: Key('effect-$name'),
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(child: Text(name)),
          Text('${before.toStringAsFixed(1)}% → ${after.toStringAsFixed(1)}%'),
          const SizedBox(width: 8),
          Icon(icon, size: 18, color: color),
        ],
      ),
    );
  }
}
