import '../data/medications_repository.dart';

/// D-49 "Add to my reminders": turns a doctor's prescription line into an add-form draft.
///
/// `medicationDetails` is built by the API as "{name} {dosage}, {frequency}[, for {duration}]"
/// with the frequency from the prescription form's fixed list, e.g.
/// "Losartan 50mg, Once daily, morning, for 3 months". The patient checks it before saving.
MedicationDraft draftFromPrescription(String details) {
  final parts = details.split(',').map((p) => p.trim()).where((p) => p.isNotEmpty).toList();
  final head = parts.isEmpty ? details.trim() : parts.first;
  final dose = RegExp(r'\s(\d[\d.]*\s*[A-Za-z%]+)$').firstMatch(head);
  final name = dose == null ? head : head.substring(0, dose.start).trim();
  final rest = parts.skip(1).join(' ').toLowerCase();
  return MedicationDraft(
    name: name.isEmpty ? head : name,
    dosage: dose?.group(1) ?? '',
    schedule: _schedule(rest),
  );
}

String _schedule(String frequency) {
  if (frequency.contains('as needed')) return 'as_needed';
  if (frequency.contains('three times')) return '08:00,14:00,20:00';
  if (frequency.contains('twice')) return '08:00,20:00';
  if (frequency.contains('evening')) return '20:00';
  return '08:00'; // once daily / once daily, morning
}

/// True when the patient already tracks this medicine (same name, ignoring case).
bool alreadyTracked(String prescriptionDetails, Iterable<String> trackedNames) {
  final name = draftFromPrescription(prescriptionDetails).name.toLowerCase();
  return trackedNames.any((n) => n.trim().toLowerCase() == name);
}
