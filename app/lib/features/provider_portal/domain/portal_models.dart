import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/constants/enums.dart';
import '../../../shared/models/health_models.dart';

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
  const PatientRow({required this.patient, this.latestReading, this.latestRisk});

  final PortalPatient patient;
  final VitalReading? latestReading;
  final RiskScore? latestRisk;

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
  });

  final String id;
  final String patientId;
  final ClinicalAlertType type;
  final RiskLevel severity;
  final String message;
  final ClinicalAlertStatus status;
  final DateTime createdAt;

  factory ClinicalAlert.fromFirestore(String id, Map<String, dynamic> d) => ClinicalAlert(
    id: id,
    patientId: d['patientId'] as String,
    type: ClinicalAlertType.fromValue(d['type'] as String),
    severity: RiskLevel.fromValue(d['severity'] as String),
    message: d['message'] as String? ?? '',
    status: ClinicalAlertStatus.fromValue(d['status'] as String),
    createdAt: _time(d['createdAt']),
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

/// `care_plans` (Table 4.2.3.12): one living plan per patient.
class CarePlan {
  const CarePlan({required this.content, required this.updatedAt});

  final String content;
  final DateTime updatedAt;

  factory CarePlan.fromFirestore(Map<String, dynamic> d) =>
      CarePlan(content: d['content'] as String? ?? '', updatedAt: _time(d['updatedAt']));
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
