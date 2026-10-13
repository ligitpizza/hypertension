import '../../../core/constants/enums.dart';
import 'portal_models.dart';

/// UC8.1 / UC8.2: search by name, filter by ML risk level, highest risk first.
///
/// An empty [levels] set means "All" (UC8.2 A1). Patients without a risk score yet
/// only appear under "All".
List<PatientRow> filterPatients(
  List<PatientRow> rows, {
  Set<RiskLevel> levels = const {},
  String query = '',
}) {
  final q = query.trim().toLowerCase();
  return [
    for (final r in rows)
      if ((levels.isEmpty || levels.contains(r.riskLevel)) &&
          (q.isEmpty || r.patient.name.toLowerCase().contains(q)))
        r,
  ]..sort(comparePriority);
}

/// Highest risk first; then the most recent reading; then name.
int comparePriority(PatientRow a, PatientRow b) {
  final byRisk = (b.riskLevel?.index ?? -1).compareTo(a.riskLevel?.index ?? -1);
  if (byRisk != 0) return byRisk;
  final at = a.lastUpdate, bt = b.lastUpdate;
  if (at != null && bt != null && at != bt) return bt.compareTo(at);
  if (at != bt) return at == null ? 1 : -1;
  return a.patient.name.toLowerCase().compareTo(b.patient.name.toLowerCase());
}

/// Patient counts per risk level for the summary cards and filter chips.
Map<RiskLevel, int> riskCounts(List<PatientRow> rows) => {
  for (final level in RiskLevel.values) level: rows.where((r) => r.riskLevel == level).length,
};

/// Open alerts, most severe first then newest (FR-8.4 priority alerts panel).
List<ClinicalAlert> prioritiseAlerts(List<ClinicalAlert> alerts) =>
    [
      for (final a in alerts)
        if (a.status == ClinicalAlertStatus.open) a,
    ]..sort((a, b) {
      final bySeverity = b.severity.index.compareTo(a.severity.index);
      return bySeverity != 0 ? bySeverity : b.createdAt.compareTo(a.createdAt);
    });

/// Fig 4.3.12.2: the red banner shows the newest open critical alert, if any.
ClinicalAlert? criticalBanner(List<ClinicalAlert> alerts) =>
    prioritiseAlerts(alerts).where((a) => a.severity == RiskLevel.critical).firstOrNull;

/// "2 hrs ago" style label for the Last Update column.
String timeAgo(DateTime then, DateTime now) {
  final d = now.difference(then);
  if (d.inMinutes < 1) return 'Just now';
  if (d.inMinutes < 60) return '${d.inMinutes} min ago';
  if (d.inHours < 24) return '${d.inHours} hr${d.inHours == 1 ? '' : 's'} ago';
  if (d.inDays == 1) return 'Yesterday';
  return '${d.inDays} days ago';
}

int? ageOn(DateTime? dob, DateTime now) {
  if (dob == null) return null;
  var age = now.year - dob.year;
  if (now.month < dob.month || (now.month == dob.month && now.day < dob.day)) age--;
  return age;
}

/// Smart templates on the Consultation Notes screen (Fig 4.3.12.5).
const noteTemplates = {
  'SOAP Note': 'S: \nO: \nA: \nP: ',
  'Hypertension F/U':
      'Hypertension follow-up\n'
      'Home BP readings: \n'
      'Symptoms (headache, dizziness, chest pain, breathlessness): \n'
      'Medication adherence: \n'
      'Lifestyle (salt, activity, smoking, alcohol): \n'
      'Assessment: \n'
      'Plan / next review: ',
  'Medication Adjustment':
      'Medication adjustment\n'
      'Current regimen: \n'
      'Reason for change: \n'
      'Change made: \n'
      'Monitoring (BP, potassium, kidney function): \n'
      'Review date: ',
};
