import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/constants/enums.dart';
import '../../../shared/models/health_models.dart';

export '../../../shared/models/health_models.dart' show CarePlan;

DateTime _time(Object? v) =>
    v is Timestamp ? v.toDate() : (v is DateTime ? v : DateTime.fromMillisecondsSinceEpoch(0));

/// An assigned patient's `users` document (FR-8.1), as much as the portal shows.
class PortalPatient {
  const PortalPatient({required this.uid, required this.name, this.dateOfBirth, this.gender});

  final String uid;
  final String name;
  final DateTime? dateOfBirth;
  final String? gender;

  factory PortalPatient.fromFirestore(String uid, Map<String, dynamic> d) => PortalPatient(
    uid: uid,
    name: d['name'] as String? ?? 'Unnamed patient',
    dateOfBirth: d['dateOfBirth'] == null ? null : _time(d['dateOfBirth']),
    gender: d['gender'] as String?,
  );
}

/// One row of the doctor dashboard: patient + latest reading + latest risk score.
class PatientRow {
  const PatientRow({
    required this.patient,
    this.latestReading,
    this.latestRisk,
    this.emergency = false,
  });

  final PortalPatient patient;
  final VitalReading? latestReading;
  final RiskScore? latestRisk;

  /// D-37: an open critical alert exists for this patient (flagged and listed first).
  final bool emergency;

  /// Null until the patient has a risk score (three readings, UC9.1).
  RiskLevel? get riskLevel => latestRisk?.overallLevel;

  DateTime? get lastUpdate => latestReading?.timestamp;
}

/// `clinical_alerts` (D-32), raised by Module 9.
class ClinicalAlert {
  const ClinicalAlert({
    required this.id,
    required this.patientId,
    required this.type,
    required this.severity,
    required this.message,
    required this.status,
    required this.createdAt,
    this.acknowledgedAt,
  });

  final String id;
  final String patientId;
  final ClinicalAlertType type;
  final RiskLevel severity;
  final String message;
  final ClinicalAlertStatus status;
  final DateTime createdAt;

  /// When the doctor acknowledged or dismissed it (D-32); null while open.
  final DateTime? acknowledgedAt;

  factory ClinicalAlert.fromFirestore(String id, Map<String, dynamic> d) => ClinicalAlert(
    id: id,
    patientId: d['patientId'] as String,
    type: ClinicalAlertType.fromValue(d['type'] as String),
    severity: RiskLevel.fromValue(d['severity'] as String),
    message: d['message'] as String? ?? '',
    status: ClinicalAlertStatus.fromValue(d['status'] as String),
    createdAt: _time(d['createdAt']),
    acknowledgedAt: d['acknowledgedAt'] == null ? null : _time(d['acknowledgedAt']),
  );
}

/// `clinical_notes` (Table 4.2.3.10).
class ClinicalNote {
  const ClinicalNote({required this.id, required this.content, required this.createdAt});

  final String id;
  final String content;
  final DateTime createdAt;

  factory ClinicalNote.fromFirestore(String id, Map<String, dynamic> d) => ClinicalNote(
    id: id,
    content: d['content'] as String? ?? '',
    createdAt: _time(d['createdAt']),
  );
}

/// `prescriptions` (Table 4.2.3.11).
class Prescription {
  const Prescription({
    required this.id,
    required this.medicationDetails,
    required this.isRecurring,
    required this.issuedAt,
  });

  final String id;
  final String medicationDetails;
  final bool isRecurring;
  final DateTime issuedAt;

  factory Prescription.fromFirestore(String id, Map<String, dynamic> d) => Prescription(
    id: id,
    medicationDetails: d['medicationDetails'] as String? ?? '',
    isRecurring: d['isRecurring'] as bool? ?? false,
    issuedAt: _time(d['issuedAt']),
  );
}

/// A drug interaction returned with a DRUG_INTERACTION error (UC8.4 E1).
class InteractionWarning {
  const InteractionWarning({
    required this.existingDrug,
    required this.severity,
    required this.message,
  });

  final String existingDrug;
  final String severity; // minor | major | critical
  final String message;

  bool get isCritical => severity == 'critical';

  static List<InteractionWarning> fromDetails(Object? details) => [
    if (details is List)
      for (final d in details.whereType<Map<dynamic, dynamic>>())
        InteractionWarning(
          existingDrug: '${d['existingDrug']}',
          severity: '${d['severity']}',
          message: '${d['message']}',
        ),
  ];
}

/// D-44: the model's risk at the BP before the first medicine vs the BP since, with every
/// other input (including the medication flag) held the same.
class MedicationEffect {
  const MedicationEffect({
    required this.status,
    this.firstMedication,
    this.startedAt,
    this.daysOnMedication,
    this.early = false,
    this.bpBefore,
    this.bpAfter,
    this.readingsBefore = 0,
    this.readingsAfter = 0,
    this.complications = const {},
  });

  /// ok | no_medication | no_baseline | no_followup | model_unavailable
  final String status;
  final String? firstMedication;
  final DateTime? startedAt;
  final int? daysOnMedication;
  final bool early;
  final (double, double)? bpBefore;
  final (double, double)? bpAfter;
  final int readingsBefore;
  final int readingsAfter;

  /// complication key -> (before %, after %).
  final Map<String, (double, double)> complications;

  static (double, double)? _bp(Object? v) =>
      v is Map ? ((v['systolic'] as num).toDouble(), (v['diastolic'] as num).toDouble()) : null;

  factory MedicationEffect.fromJson(Map<String, dynamic> d) => MedicationEffect(
    status: d['status'] as String? ?? 'no_medication',
    firstMedication: d['firstMedication'] as String?,
    startedAt: DateTime.tryParse(d['startedAt'] as String? ?? '')?.toLocal(),
    daysOnMedication: (d['daysOnMedication'] as num?)?.toInt(),
    early: d['early'] as bool? ?? false,
    bpBefore: _bp(d['bpBefore']),
    bpAfter: _bp(d['bpAfter']),
    readingsBefore: (d['readingsBefore'] as num?)?.toInt() ?? 0,
    readingsAfter: (d['readingsAfter'] as num?)?.toInt() ?? 0,
    complications: {
      for (final e in ((d['complications'] as Map?) ?? const {}).entries)
        '${e.key}': (
          ((e.value as Map)['before'] as num).toDouble(),
          ((e.value as Map)['after'] as num).toDouble(),
        ),
    },
  );
}
