import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/enums.dart';
import '../../../core/utils/bp_classifier.dart';
import '../../../core/utils/risk_style.dart';
import '../../../shared/models/health_models.dart';
import '../domain/portal_models.dart';

/// Shared bits of the doctor portal (Module 8).

class RiskChip extends StatelessWidget {
  const RiskChip({super.key, required this.level});

  /// Null when the patient has no risk score yet (fewer than three readings).
  final RiskLevel? level;

  @override
  Widget build(BuildContext context) {
    final color = level == null ? Theme.of(context).disabledColor : riskColor(level!);
    return Chip(
      visualDensity: VisualDensity.compact,
      avatar: CircleAvatar(backgroundColor: color, radius: 5),
      label: Text(level == null ? 'No score yet' : riskLabel(level!)),
    );
  }
}

class BpText extends StatelessWidget {
  const BpText({super.key, required this.reading, this.style});

  final VitalReading? reading;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final r = reading;
    if (r == null) return Text('--/--', style: style);
    final color = BpClassifier.color(BpClassifier.classify(r.systolic, r.diastolic));
    return Text(
      '${r.systolic}/${r.diastolic}',
      style: (style ?? const TextStyle()).copyWith(color: color, fontWeight: FontWeight.w600),
    );
  }
}

class SectionCard extends StatelessWidget {
  const SectionCard({super.key, required this.title, required this.child, this.trailing});

  final String title;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(title, style: Theme.of(context).textTheme.titleMedium)),
              ?trailing,
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    ),
  );
}

/// Loading / error / empty states for a portal section.
class AsyncSection<T> extends StatelessWidget {
  const AsyncSection({
    super.key,
    required this.value,
    required this.builder,
    this.isEmpty,
    this.emptyText = 'Nothing here yet.',
  });

  final AsyncValue<T> value;
  final Widget Function(T data) builder;
  final bool Function(T data)? isEmpty;
  final String emptyText;

  @override
  // A later stream error keeps showing the last data rather than replacing it.
  Widget build(BuildContext context) => value.when(
    skipError: true,
    loading: () => const Padding(
      padding: EdgeInsets.all(16),
      child: Center(child: CircularProgressIndicator()),
    ),
    error: (e, _) => Text(
      'Could not load this section. Check your connection and refresh.',
      style: TextStyle(color: Theme.of(context).colorScheme.error),
    ),
    data: (d) => (isEmpty?.call(d) ?? false) ? Text(emptyText) : builder(d),
  );
}

String formatDate(DateTime d) {
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
  return '${d.day} ${months[d.month - 1]} ${d.year}, $h:${d.minute.toString().padLeft(2, '0')} '
      '${d.hour < 12 ? 'AM' : 'PM'}';
}

String alertTypeLabel(ClinicalAlertType t) => switch (t) {
  ClinicalAlertType.threshold => 'BP spike',
  ClinicalAlertType.riskEscalation => 'Risk escalation',
  ClinicalAlertType.deterioration => 'Deteriorating trend',
  ClinicalAlertType.medicationReview => 'Medication review',
  ClinicalAlertType.triage => 'Symptom triage',
  ClinicalAlertType.flaggedMessage => 'Flagged message',
  ClinicalAlertType.lowAdherence => 'Missed medication',
};

/// "Raised 14 Oct 2026, 11:32 PM · Acknowledged 14 Oct 2026, 11:40 PM" (history tab).
String alertTimeline(ClinicalAlert a) {
  final raised = 'Raised ${formatDate(a.createdAt)}';
  return switch (a.status) {
    ClinicalAlertStatus.open => '$raised · Open',
    ClinicalAlertStatus.acknowledged =>
      '$raised · Acknowledged${a.acknowledgedAt == null ? '' : ' ${formatDate(a.acknowledgedAt!)}'}',
    ClinicalAlertStatus.dismissed =>
      '$raised · Dismissed${a.acknowledgedAt == null ? '' : ' ${formatDate(a.acknowledgedAt!)}'}',
  };
}
