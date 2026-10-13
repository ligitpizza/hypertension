import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/constants/enums.dart';
import '../../../shared/services/api/api_client.dart';

/// `symptom_catalog` entry (Table 4.2.3.18; `isRedFlag` per D-10).
class SymptomOption {
  const SymptomOption({
    required this.id,
    required this.name,
    required this.category,
    this.isRedFlag = false,
  });

  final String id;
  final String name;
  final String category;
  final bool isRedFlag;

  factory SymptomOption.fromFirestore(String id, Map<String, dynamic> d) => SymptomOption(
    id: id,
    name: d['name'] as String? ?? id,
    category: d['category'] as String? ?? 'other',
    isRedFlag: d['isRedFlag'] as bool? ?? false,
  );
}

/// Result of POST /api/v1/triage (UC14.3).
class TriageResult {
  const TriageResult({
    required this.id,
    required this.outcome,
    required this.reason,
    required this.symptoms,
    this.systolic,
    this.diastolic,
    this.heartRate,
    this.missingInputs = const [],
    this.doctorNotified = false,
  });

  final String id;
  final TriageOutcome outcome;
  final String reason;
  final List<SymptomOption> symptoms;
  final int? systolic;
  final int? diastolic;
  final int? heartRate;

  /// UC14.1 E1: e.g. heart_rate, recent_blood_pressure, risk_score.
  final List<String> missingInputs;
  final bool doctorNotified;

  factory TriageResult.fromApi(Map<String, dynamic> j) => TriageResult(
    id: j['id'] as String,
    outcome: TriageOutcome.fromValue(j['outcome'] as String),
    reason: j['reason'] as String? ?? '',
    symptoms: [
      for (final s in j['symptoms'] as List<dynamic>? ?? const [])
        SymptomOption(
          id: (s as Map)['id'] as String,
          name: s['name'] as String,
          category: '',
          isRedFlag: s['isRedFlag'] as bool? ?? false,
        ),
    ],
    systolic: j['systolic'] as int?,
    diastolic: j['diastolic'] as int?,
    heartRate: j['heartRate'] as int?,
    missingInputs: [for (final m in j['missingInputs'] as List<dynamic>? ?? const []) m as String],
    doctorNotified: j['doctorNotified'] as bool? ?? false,
  );
}

/// A saved `triage_outcomes` document (Table 4.2.3.5).
class TriageRecord {
  const TriageRecord({
    required this.id,
    required this.outcome,
    required this.severity,
    required this.symptomIds,
    required this.generatedAt,
  });

  final String id;
  final TriageOutcome outcome;
  final TriageSeverity severity;
  final List<String> symptomIds;
  final DateTime generatedAt;

  factory TriageRecord.fromFirestore(String id, Map<String, dynamic> d) => TriageRecord(
    id: id,
    outcome: TriageOutcome.fromValue(d['outcome'] as String),
    severity: TriageSeverity.fromValue(d['severity'] as String),
    symptomIds: [for (final s in d['symptoms'] as List<dynamic>? ?? const []) '$s'],
    generatedAt:
        (d['generatedAt'] as Timestamp?)?.toDate() ?? DateTime.fromMillisecondsSinceEpoch(0),
  );
}

/// FR-14.3 (Fig 4.1.1.14 TriageCtrl). The catalog is a direct Firestore read; the
/// submission goes through FastAPI, which applies the rule table and notifies the doctor.
abstract interface class SymptomRepository {
  Stream<List<SymptomOption>> catalog();

  /// Newest first (patient dashboard emergency card, doctor triage history; D-37).
  Stream<List<TriageRecord>> outcomes(String patientId, {int limit = 20});

  Future<TriageResult> submit({
    required List<String> symptomIds,
    required TriageSeverity severity,
    required int heartRate,
    required String vitalReadingId,
  });
}

class ApiSymptomRepository implements SymptomRepository {
  ApiSymptomRepository(this._db, this._api);

  final FirebaseFirestore _db;
  final ApiClient _api;

  @override
  Stream<List<SymptomOption>> catalog() => _db
      .collection(Collections.symptomCatalog)
      .snapshots()
      .map((s) => [for (final d in s.docs) SymptomOption.fromFirestore(d.id, d.data())]);

  @override
  Stream<List<TriageRecord>> outcomes(String patientId, {int limit = 20}) => _db
      .collection(Collections.triageOutcomes)
      .where('patientId', isEqualTo: patientId)
      .orderBy('generatedAt', descending: true)
      .limit(limit)
      .snapshots()
      .map((s) => [for (final d in s.docs) TriageRecord.fromFirestore(d.id, d.data())]);

  @override
  Future<TriageResult> submit({
    required List<String> symptomIds,
    required TriageSeverity severity,
    required int heartRate,
    required String vitalReadingId,
  }) async => TriageResult.fromApi(
    await _api.submitTriage(
      symptoms: symptomIds,
      severity: severity.value,
      heartRate: heartRate,
      vitalReadingId: vitalReadingId,
    ),
  );
}
