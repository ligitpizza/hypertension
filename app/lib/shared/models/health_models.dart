import 'package:cloud_firestore/cloud_firestore.dart';

import '../../core/constants/enums.dart';

DateTime _time(Object? v) =>
    v is Timestamp ? v.toDate() : (v is DateTime ? v : DateTime.fromMillisecondsSinceEpoch(0));

/// `vital_readings` (docs/04 Table 4.2.3.3).
class VitalReading {
  const VitalReading({
    required this.id,
    required this.patientId,
    required this.systolic,
    required this.diastolic,
    required this.timestamp,
    this.heartRate,
    this.note,
  });

  final String id;
  final String patientId;
  final int systolic;
  final int diastolic;
  final int? heartRate;
  final String? note;
  final DateTime timestamp;

  factory VitalReading.fromFirestore(String id, Map<String, dynamic> d) => VitalReading(
    id: id,
    patientId: d['patientId'] as String,
    systolic: (d['systolic'] as num).round(),
    diastolic: (d['diastolic'] as num).round(),
    heartRate: (d['heartRate'] as num?)?.round(),
    note: d['note'] as String?,
    timestamp: _time(d['timestamp']),
  );
}

/// One complication entry in `risk_scores.scores` (D-03).
class ComplicationScore {
  const ComplicationScore({required this.value, required this.level, this.factors = const []});

  final double value;
  final RiskLevel level;

  /// D-40: model inputs that most raised this estimate, largest first.
  final List<String> factors;
}

/// `risk_scores` (docs/04 Table 4.2.3.4).
class RiskScore {
  const RiskScore({
    required this.id,
    required this.patientId,
    required this.scores,
    required this.generatedAt,
    required this.modelUsed,
  });

  final String id;
  final String patientId;
  final Map<Complication, ComplicationScore> scores;
  final DateTime generatedAt;
  final String modelUsed;

  /// D-03: overall level = highest of the five complication levels, computed at read time.
  RiskLevel get overallLevel => scores.values.isEmpty
      ? RiskLevel.low
      : scores.values.map((s) => s.level).reduce((a, b) => a.index >= b.index ? a : b);

  factory RiskScore.fromFirestore(String id, Map<String, dynamic> d) {
    final raw = (d['scores'] as Map?)?.cast<String, dynamic>() ?? const {};
    final scores = <Complication, ComplicationScore>{};
    for (final entry in raw.entries) {
      final c = Complication.values.where((x) => x.value == entry.key).firstOrNull;
      final m = (entry.value as Map).cast<String, dynamic>();
      if (c == null) continue;
      scores[c] = ComplicationScore(
        value: (m['value'] as num).toDouble(),
        level: RiskLevel.fromValue(m['level'] as String),
        factors: [for (final f in m['factors'] as List<dynamic>? ?? const []) '$f'],
      );
    }
    return RiskScore(
      id: id,
      patientId: d['patientId'] as String,
      scores: scores,
      generatedAt: _time(d['generatedAt']),
      modelUsed: d['modelUsed'] as String? ?? '',
    );
  }
}

/// `medications` (docs/04 Table 4.2.3.6).
class Medication {
  const Medication({
    required this.id,
    required this.patientId,
    required this.name,
    required this.dosage,
    required this.schedule,
    this.adherenceRate,
    this.quantityOnHand,
    this.refillThresholdDays = 7,
    this.createdAt,
  });

  final String id;
  final String patientId;
  final String name;
  final String dosage;

  /// D-43: "08:00,20:00" (Malaysia time) or "as_needed".
  final String schedule;
  final double? adherenceRate;

  /// D-05: doses left; null when the patient doesn't track stock.
  final double? quantityOnHand;
  final int refillThresholdDays;
  final DateTime? createdAt;

  factory Medication.fromFirestore(String id, Map<String, dynamic> d) => Medication(
    id: id,
    patientId: d['patientId'] as String,
    name: d['name'] as String? ?? '',
    dosage: d['dosage'] as String? ?? '',
    schedule: d['schedule'] as String? ?? '',
    adherenceRate: (d['adherenceRate'] as num?)?.toDouble(),
    quantityOnHand: (d['quantityOnHand'] as num?)?.toDouble(),
    refillThresholdDays: (d['refillThresholdDays'] as num?)?.toInt() ?? 7,
    createdAt: (d['createdAt'] as Timestamp?)?.toDate(),
  );
}

/// `dose_logs` (docs/04 Table 4.2.3.7). Written only by the API (D-43).
class DoseLog {
  const DoseLog({
    required this.id,
    required this.medicationId,
    required this.scheduledTime,
    required this.status,
    this.confirmedAt,
  });

  final String id;
  final String medicationId;
  final DateTime scheduledTime;
  final String status; // taken | missed
  final DateTime? confirmedAt;

  factory DoseLog.fromFirestore(String id, Map<String, dynamic> d) => DoseLog(
    id: id,
    medicationId: d['medicationId'] as String? ?? '',
    scheduledTime: _time(d['scheduledTime']),
    status: d['status'] as String? ?? '',
    confirmedAt: (d['confirmedAt'] as Timestamp?)?.toDate(),
  );
}

/// `appointments` (docs/04 Table 4.2.3.9).
class Appointment {
  const Appointment({
    required this.id,
    required this.patientId,
    required this.dateTime,
    required this.status,
    this.doctorId,
    this.type = AppointmentType.checkup,
  });

  final String id;
  final String patientId;
  final String? doctorId;
  final DateTime dateTime;
  final AppointmentStatus status;

  /// D-53.
  final AppointmentType type;

  bool get isActive =>
      status == AppointmentStatus.booked || status == AppointmentStatus.rescheduled;

  factory Appointment.fromFirestore(String id, Map<String, dynamic> d) => Appointment(
    id: id,
    patientId: d['patientId'] as String,
    doctorId: d['doctorId'] as String?,
    dateTime: _time(d['dateTime']),
    status: AppointmentStatus.fromValue(d['status'] as String),
    type: AppointmentType.fromValue(d['type'] as String?),
  );
}

/// `care_plans` (Table 4.2.3.12): one living plan per patient, written by the doctor
/// (Module 8) and read by the patient on the dashboard.
class CarePlan {
  const CarePlan({required this.content, required this.updatedAt});

  final String content;
  final DateTime updatedAt;

  factory CarePlan.fromFirestore(Map<String, dynamic> d) =>
      CarePlan(content: d['content'] as String? ?? '', updatedAt: _time(d['updatedAt']));
}

/// D-41: one saved version of the care plan (`care_plans/{patientId}/versions`).
class CarePlanVersion {
  const CarePlanVersion({required this.content, required this.savedAt});

  final String content;
  final DateTime savedAt;

  factory CarePlanVersion.fromFirestore(Map<String, dynamic> d) =>
      CarePlanVersion(content: d['content'] as String? ?? '', savedAt: _time(d['savedAt']));
}
