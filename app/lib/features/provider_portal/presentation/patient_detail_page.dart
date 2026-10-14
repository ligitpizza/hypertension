import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/enums.dart';
import '../../../core/utils/bp_classifier.dart';
import '../../../core/utils/risk_style.dart';
import '../../../shared/models/health_models.dart';
import '../../charts/domain/trend_logic.dart';
import '../../charts/presentation/bp_trend_chart.dart';
import '../../charts/presentation/risk_trend_card.dart' show complicationNames;
import '../../charts/state/trends_providers.dart';
import '../../dashboard/state/dashboard_providers.dart';
import '../../medications/domain/med_schedule.dart';
import '../domain/portal_logic.dart';
import '../domain/portal_models.dart';
import '../../symptom_checker/data/symptom_repository.dart';
import '../../symptom_checker/state/symptom_providers.dart';
import '../state/portal_providers.dart';
import '../../appointments/presentation/reassignment_dialog.dart';
import 'dose_history.dart';
import 'medication_effect_card.dart';
import 'portal_prescription_tile.dart';
import 'portal_widgets.dart';
import '../../../core/utils/ic_number.dart';

/// Fig 4.3.12.4 Patient Detail (FR-8.2; UC8.3): vitals, risk, BP trend, medications,
/// prescriptions, care plan and clinical notes for one assigned patient.
class PatientDetailPage extends ConsumerStatefulWidget {
  const PatientDetailPage({super.key, required this.patientId});

  final String patientId;

  @override
  ConsumerState<PatientDetailPage> createState() => _PatientDetailPageState();
}

class _PatientDetailPageState extends ConsumerState<PatientDetailPage> {
  TrendRange _range = TrendRange.month;

  String get id => widget.patientId;

  @override
  Widget build(BuildContext context) {
    final patient = ref.watch(portalPatientProvider(id));
    final now = ref.watch(nowProvider)();
    final wide = MediaQuery.sizeOf(context).width >= 1000;

    return patient.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, _) => const _Message(
        'You can only view patients assigned to you. Check the patient list and try again.',
      ),
      data: (p) {
        if (p == null) return const _Message('Patient not found.');
        final top = [
          Expanded(child: _VitalsAndRisk(patientId: id)),
          const SizedBox(width: 16, height: 16),
          Expanded(flex: wide ? 2 : 1, child: _trendCard(now)),
        ];
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                key: const Key('back-to-patients'),
                onPressed: () => context.go('/doctor'),
                icon: const Icon(Icons.arrow_back),
                label: const Text('My patients'),
              ),
            ),
            _Header(patient: p, now: now),
            const SizedBox(height: 16),
            if (wide)
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: top)
            else ...[
              _VitalsAndRisk(patientId: id),
              const SizedBox(height: 16),
              _trendCard(now),
            ],
            const SizedBox(height: 16),
            _HistoryTabs(patientId: id),
          ],
        );
      },
    );
  }

  Widget _trendCard(DateTime now) {
    final readings = ref.watch(readingsInRangeProvider((id, _range)));
    return SectionCard(
      title: 'Blood pressure trend',
      trailing: SegmentedButton<TrendRange>(
        showSelectedIcon: false,
        segments: [
          for (final r in [TrendRange.week, TrendRange.month, TrendRange.quarter])
            ButtonSegment(value: r, label: Text(r.label)),
        ],
        selected: {_range},
        onSelectionChanged: (s) => setState(() => _range = s.first),
      ),
      child: AsyncSection(
        value: readings,
        isEmpty: (r) => r.isEmpty,
        emptyText: 'No readings in this period.',
        builder: (r) => SizedBox(
          height: 240,
          child: BpTrendChart(points: buildPoints(r, _range, now), range: _range, now: now),
        ),
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Text(text, textAlign: TextAlign.center),
    ),
  );
}

class _Header extends StatelessWidget {
  const _Header({required this.patient, required this.now});

  final PortalPatient patient;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final age = ageOn(patient.dateOfBirth, now);
    final facts = [
      if (age != null) '$age years',
      if (patient.gender != null) patient.gender![0].toUpperCase() + patient.gender!.substring(1),
      if (patient.icNumber != null) 'IC ${maskIc(patient.icNumber)}',
    ].join(' · ');
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Wrap(
          spacing: 16,
          runSpacing: 12,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            CircleAvatar(
              radius: 28,
              child: Text(patient.name.isEmpty ? '?' : patient.name[0].toUpperCase()),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(patient.name, style: Theme.of(context).textTheme.headlineSmall),
                if (facts.isNotEmpty) Text(facts),
              ],
            ),
            FilledButton.icon(
              key: const Key('action-note'),
              onPressed: () => context.go('/doctor/patient/${patient.uid}/notes'),
              icon: const Icon(Icons.edit_note),
              label: const Text('Add note'),
            ),
            OutlinedButton.icon(
              key: const Key('action-prescribe'),
              onPressed: () => context.go('/doctor/patient/${patient.uid}/prescriptions'),
              icon: const Icon(Icons.medication_outlined),
              label: const Text('Prescribe'),
            ),
            OutlinedButton.icon(
              key: const Key('action-care-plan'),
              onPressed: () => context.go('/doctor/patient/${patient.uid}/care-plan'),
              icon: const Icon(Icons.assignment_outlined),
              label: const Text('Care plan'),
            ),
            // D-54: hand this patient to another doctor (the admin decides).
            TextButton.icon(
              key: const Key('action-reassign'),
              onPressed: () => requestReassignment(context, patient.uid, patient.name),
              icon: const Icon(Icons.swap_horiz),
              label: const Text('Request reassignment'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Latest BP and the current risk score with each complication (FR-9.2, FR-9.3).
class _VitalsAndRisk extends ConsumerWidget {
  const _VitalsAndRisk({required this.patientId});

  final String patientId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reading = ref.watch(patientLatestReadingProvider(patientId));
    final risk = ref.watch(patientLatestRiskProvider(patientId));
    final level = risk.value?.overallLevel;
    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: level == null ? Colors.transparent : riskColor(level), width: 2),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Latest reading', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            AsyncSection<VitalReading?>(
              value: reading,
              isEmpty: (r) => r == null,
              emptyText: 'No readings yet.',
              builder: (r) => Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  BpText(
                    key: const Key('detail-latest-bp'),
                    reading: r,
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  Text(
                    '${BpClassifier.label(BpClassifier.classify(r!.systolic, r.diastolic))} · '
                    '${formatDate(r.timestamp)}',
                  ),
                  if (r.heartRate != null) Text('Heart rate ${r.heartRate} bpm (camera estimate)'),
                ],
              ),
            ),
            const Divider(height: 24),
            Row(
              children: [
                Expanded(
                  child: Text('Risk assessment', style: Theme.of(context).textTheme.titleMedium),
                ),
                RiskChip(level: level),
              ],
            ),
            AsyncSection<RiskScore?>(
              value: risk,
              isEmpty: (s) => s == null,
              emptyText: 'No risk score yet (needs three readings).',
              builder: (s) => Column(
                children: [
                  for (final c in Complication.values)
                    if (s!.scores[c] != null)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(child: Text(complicationNames[c]!)),
                                Text(riskPercent(s.scores[c]!.value)),
                                const SizedBox(width: 8),
                                CircleAvatar(
                                  radius: 5,
                                  backgroundColor: riskColor(s.scores[c]!.level),
                                ),
                              ],
                            ),
                            // D-40 contributing factors (Fig 4.3.12.4).
                            // Only Moderate and above are explained (D-40, Ping 2026-10-14).
                            if (s.scores[c]!.factors.isNotEmpty &&
                                s.scores[c]!.level != RiskLevel.low)
                              Text(
                                'Raised by: ${s.scores[c]!.factors.map(factorLabel).join(', ')}',
                                key: Key('factors-${c.value}'),
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                          ],
                        ),
                      ),
                  const SizedBox(height: 4),
                  if (s!.scores.values.any((x) => x.factors.isNotEmpty))
                    Text(
                      '"Raised by" lists the inputs that most increased each estimate for this '
                      'patient (model associations, not proven causes).',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Scored ${formatDate(s.generatedAt)} · ${modelLabel(s.modelUsed)}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Tabs for the rest of the record (UC8.3 E1: each tab has its own empty state).
class _HistoryTabs extends ConsumerWidget {
  const _HistoryTabs({required this.patientId});

  final String patientId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final readings = ref.watch(patientReadingsProvider(patientId));
    final meds = ref.watch(patientMedicationsProvider(patientId));
    final rx = ref.watch(patientPrescriptionsProvider(patientId));
    final plan = ref.watch(patientCarePlanProvider(patientId));
    final notes = ref.watch(patientNotesProvider(patientId));
    final alerts = ref.watch(patientAlertsProvider(patientId));
    final triage = ref.watch(patientTriageProvider(patientId));

    return DefaultTabController(
      length: 5,
      child: Card(
        child: Column(
          children: [
            const TabBar(
              isScrollable: true,
              tabs: [
                Tab(text: 'Vitals'),
                Tab(text: 'Medications'),
                Tab(text: 'Care plan'),
                Tab(text: 'Clinical notes'),
                Tab(text: 'Alerts & triage'),
              ],
            ),
            SizedBox(
              height: 360,
              child: TabBarView(
                children: [
                  _pad(
                    AsyncSection(
                      value: readings,
                      isEmpty: (r) => r.isEmpty,
                      emptyText: 'No readings recorded yet.',
                      builder: (r) => ListView(
                        children: [
                          for (final x in r)
                            ListTile(
                              dense: true,
                              title: BpText(reading: x),
                              subtitle: Text(
                                [
                                  formatDate(x.timestamp),
                                  if (x.heartRate != null) 'HR ${x.heartRate} (estimate)',
                                  if (x.note != null) x.note!,
                                ].join(' · '),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  _pad(
                    ListView(
                      children: [
                        Text(
                          'Patient medication list',
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                        AsyncSection(
                          value: meds,
                          isEmpty: (m) => m.isEmpty,
                          emptyText: 'The patient has not added any medications.',
                          builder: (m) => Column(
                            children: [
                              for (final x in m) ...[
                                ListTile(
                                  dense: true,
                                  title: Text('${x.name} ${x.dosage}'),
                                  subtitle: Text(describeSchedule(x.schedule)),
                                  trailing: x.adherenceRate == null
                                      ? null
                                      : Text('Adherence ${x.adherenceRate!.round()}%'),
                                ),
                                DoseHistory(medication: x),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                        MedicationEffectCard(patientId: patientId),
                        const SizedBox(height: 12),
                        Text('Prescriptions', style: Theme.of(context).textTheme.titleSmall),
                        AsyncSection(
                          value: rx,
                          isEmpty: (p) => p.isEmpty,
                          emptyText: 'No prescriptions issued yet.',
                          builder: (p) => Column(
                            children: [
                              for (final x in p)
                                PortalPrescriptionTile(prescription: x, patientId: patientId),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  _pad(
                    AsyncSection<CarePlan?>(
                      value: plan,
                      isEmpty: (p) => p == null,
                      emptyText: 'No care plan yet. Use "Care plan" above to write one.',
                      builder: (p) => ListView(
                        children: [
                          Text(
                            'Updated ${formatDate(p!.updatedAt)}',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                          const SizedBox(height: 8),
                          SelectableText(p.content),
                        ],
                      ),
                    ),
                  ),
                  _pad(NotesList(notes: notes)),
                  _pad(_AlertHistory(alerts: alerts, triage: triage)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _pad(Widget child) => Padding(padding: const EdgeInsets.all(16), child: child);
}

/// Past notes, newest first (also shown under the editor after saving, Fig 4.3.12.6).
class NotesList extends StatelessWidget {
  const NotesList({super.key, required this.notes, this.shrinkWrap = false});

  final AsyncValue<List<ClinicalNote>> notes;
  final bool shrinkWrap;

  @override
  Widget build(BuildContext context) => AsyncSection(
    value: notes,
    isEmpty: (n) => n.isEmpty,
    emptyText: 'No clinical notes yet.',
    builder: (n) => ListView.separated(
      shrinkWrap: shrinkWrap,
      physics: shrinkWrap ? const NeverScrollableScrollPhysics() : null,
      itemCount: n.length,
      separatorBuilder: (_, _) => const Divider(),
      itemBuilder: (_, i) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(formatDate(n[i].createdAt), style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 4),
          SelectableText(n[i].content),
        ],
      ),
    ),
  );
}

/// D-37: the patient's alert and symptom-check history ("full event logged to the record").
class _AlertHistory extends StatelessWidget {
  const _AlertHistory({required this.alerts, required this.triage});

  final AsyncValue<List<ClinicalAlert>> alerts;
  final AsyncValue<List<TriageRecord>> triage;

  static String _outcome(TriageOutcome o) => switch (o) {
    TriageOutcome.seekEmergencyCare => 'Seek emergency care',
    TriageOutcome.contactDoctor => 'Contact doctor',
    TriageOutcome.monitorAtHome => 'Monitor at home',
  };

  @override
  Widget build(BuildContext context) => ListView(
    children: [
      Text('Alerts', style: Theme.of(context).textTheme.titleSmall),
      AsyncSection(
        value: alerts,
        isEmpty: (a) => a.isEmpty,
        emptyText: 'No alerts for this patient.',
        builder: (a) => Column(
          children: [
            for (final x in a)
              ListTile(
                dense: true,
                leading: CircleAvatar(radius: 6, backgroundColor: riskColor(x.severity)),
                title: Text('${alertTypeLabel(x.type)} · ${x.severity.value}'),
                subtitle: Text('${alertTimeline(x)}\n${x.message}'),
                isThreeLine: true,
              ),
          ],
        ),
      ),
      const SizedBox(height: 12),
      Text('Symptom checks', style: Theme.of(context).textTheme.titleSmall),
      AsyncSection(
        value: triage,
        isEmpty: (t) => t.isEmpty,
        emptyText: 'No symptom checks yet.',
        builder: (t) => Column(
          children: [
            for (final x in t)
              ListTile(
                key: Key('triage-${x.id}'),
                dense: true,
                title: Text('${_outcome(x.outcome)} · ${x.severity.value}'),
                subtitle: Text(
                  '${formatDate(x.generatedAt)} · ${x.symptomIds.map((s) => s.replaceAll('_', ' ')).join(', ')}',
                ),
              ),
          ],
        ),
      ),
    ],
  );
}
