import 'package:flutter_test/flutter_test.dart';
import 'package:hypertension/core/constants/enums.dart';
import 'package:hypertension/features/provider_portal/domain/portal_logic.dart';
import 'package:hypertension/features/provider_portal/domain/portal_models.dart';
import 'package:hypertension/shared/models/health_models.dart';

// Module 8 dashboard logic (FR-8.1, FR-8.4; UC8.1, UC8.2, UC8.6).
final now = DateTime(2026, 10, 13, 12);

PatientRow row(String name, RiskLevel? level, {int hoursAgo = 1}) => PatientRow(
  patient: PortalPatient(uid: name, name: name),
  latestReading: VitalReading(
    id: 'r-$name',
    patientId: name,
    systolic: 130,
    diastolic: 85,
    timestamp: now.subtract(Duration(hours: hoursAgo)),
  ),
  latestRisk: level == null
      ? null
      : RiskScore(
          id: 's-$name',
          patientId: name,
          scores: {Complication.stroke: ComplicationScore(value: 0.2, level: level)},
          generatedAt: now,
          modelUsed: 'XGBoost v1',
        ),
);

ClinicalAlert alert(String id, RiskLevel severity, {int minutesAgo = 0, bool open = true}) =>
    ClinicalAlert(
      id: id,
      patientId: 'p',
      type: ClinicalAlertType.threshold,
      severity: severity,
      message: 'm',
      status: open ? ClinicalAlertStatus.open : ClinicalAlertStatus.dismissed,
      createdAt: now.subtract(Duration(minutes: minutesAgo)),
    );

void main() {
  final rows = [
    row('Mei Lin', RiskLevel.low),
    row('Siti Aminah', RiskLevel.critical, hoursAgo: 5),
    row('Ali Hassan', RiskLevel.high),
    row('New Patient', null),
    row('Sarah Jenkins', RiskLevel.critical, hoursAgo: 2),
  ];

  List<String> names(List<PatientRow> r) => [for (final x in r) x.patient.name];

  test('FR-8.1 highest risk first, then most recent reading; unscored last', () {
    expect(names(filterPatients(rows)), [
      'Sarah Jenkins',
      'Siti Aminah',
      'Ali Hassan',
      'Mei Lin',
      'New Patient',
    ]);
  });

  test('UC8.2 filter by one or more risk levels', () {
    expect(names(filterPatients(rows, levels: {RiskLevel.high})), ['Ali Hassan']);
    expect(names(filterPatients(rows, levels: {RiskLevel.critical, RiskLevel.low})), [
      'Sarah Jenkins',
      'Siti Aminah',
      'Mei Lin',
    ]);
  });

  test('UC8.2 A1 clearing the filter restores the full list', () {
    expect(filterPatients(rows, levels: {}).length, rows.length);
  });

  test('FR-8.1 search by name, case-insensitive, combined with the filter', () {
    expect(names(filterPatients(rows, query: '  si ')), ['Siti Aminah']);
    expect(names(filterPatients(rows, query: 'a', levels: {RiskLevel.critical})), [
      'Sarah Jenkins',
      'Siti Aminah',
    ]);
  });

  test('risk counts per level', () {
    expect(riskCounts(rows), {
      RiskLevel.low: 1,
      RiskLevel.moderate: 0,
      RiskLevel.high: 1,
      RiskLevel.critical: 2,
    });
  });

  test('FR-8.4 open alerts sorted by severity then newest; closed ones hidden', () {
    final sorted = prioritiseAlerts([
      alert('old-high', RiskLevel.high, minutesAgo: 60),
      alert('crit', RiskLevel.critical, minutesAgo: 30),
      alert('new-high', RiskLevel.high, minutesAgo: 5),
      alert('closed', RiskLevel.critical, open: false),
    ]);
    expect([for (final a in sorted) a.id], ['crit', 'new-high', 'old-high']);
  });

  test('Fig 4.3.12.2 critical banner only for an open critical alert', () {
    expect(criticalBanner([alert('h', RiskLevel.high)]), isNull);
    expect(criticalBanner([alert('h', RiskLevel.high), alert('c', RiskLevel.critical)])?.id, 'c');
    expect(criticalBanner([alert('c', RiskLevel.critical, open: false)]), isNull);
  });

  test('time ago labels', () {
    expect(timeAgo(now, now), 'Just now');
    expect(timeAgo(now.subtract(const Duration(minutes: 10)), now), '10 min ago');
    expect(timeAgo(now.subtract(const Duration(hours: 1)), now), '1 hr ago');
    expect(timeAgo(now.subtract(const Duration(hours: 26)), now), 'Yesterday');
    expect(timeAgo(now.subtract(const Duration(days: 4)), now), '4 days ago');
  });

  test('UC8.4 E1 interaction details parse from the API error', () {
    final w = InteractionWarning.fromDetails([
      {
        'newDrug': 'Aliskiren',
        'existingDrug': 'Lisinopril',
        'severity': 'critical',
        'message': 'x',
      },
    ]);
    expect(w.single.existingDrug, 'Lisinopril');
    expect(w.single.isCritical, isTrue);
    expect(InteractionWarning.fromDetails(null), isEmpty);
  });

  test('note templates cover the three Fig 4.3.12.5 templates', () {
    expect(noteTemplates.keys, ['SOAP Note', 'Hypertension F/U', 'Medication Adjustment']);
  });

  test('model label shows each distinct model once', () {
    expect(
      modelLabel('stroke:XGBoost v1; cad:XGBoost v1; ckd:RandomForest v1'),
      'XGBoost v1, RandomForest v1',
    );
    expect(modelLabel('XGBoost v1'), 'XGBoost v1');
  });
}
