/// Prescription frequencies offered to doctors (Fig 4.3.12.7) and patients (D-50).
const frequencies = [
  'Once daily',
  'Once daily, morning',
  'Once daily, evening',
  'Twice daily',
  'Three times daily',
  'As needed',
];

/// The parts of a `medicationDetails` line, built by the API as
/// "{name} {dosage}, {frequency}[, for {duration}][, from {clinic}]".
typedef PrescriptionParts = ({
  String name,
  String dosage,
  String? frequency,
  String? duration,
  String? clinic,
});

PrescriptionParts parsePrescription(String details) {
  final parts = details.split(',').map((p) => p.trim()).where((p) => p.isNotEmpty).toList();
  final head = parts.isEmpty ? details.trim() : parts.first;
  final dose = RegExp(r'\s(\d[\d.]*\s*[A-Za-z%]+)$').firstMatch(head);
  final name = dose == null ? head : head.substring(0, dose.start).trim();
  String? duration, clinic;
  final rest = <String>[];
  for (final p in parts.skip(1)) {
    if (p.startsWith('for ')) {
      duration = p.substring(4);
    } else if (p.startsWith('from ')) {
      clinic = p.substring(5);
    } else {
      rest.add(p);
    }
  }
  final freqText = rest.join(', ');
  final frequency = frequencies.where((f) => f.toLowerCase() == freqText.toLowerCase()).firstOrNull;
  return (
    name: name.isEmpty ? head : name,
    dosage: dose?.group(1) ?? '',
    frequency: frequency,
    duration: duration,
    clinic: clinic,
  );
}
