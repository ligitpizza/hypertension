import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/constants/enums.dart';
import '../../../shared/models/health_models.dart';

/// Fig 4.1.1.4 TrendCtrl reads: readings in a range and risk-score history. Direct
/// Firestore listeners (NFR-1.1); rules allow the patient, the assigned doctor
/// (Module 8 reuse) and the linked family member.
abstract interface class TrendsRepository {
  /// Readings since [from], newest first (served by the patientId+timestamp index).
  Stream<List<VitalReading>> readingsSince(String patientId, DateTime from);

  /// Risk scores, newest first (UC4.4).
  Stream<List<RiskScore>> riskHistory(String patientId, {int limit = 60});
}

class FirestoreTrendsRepository implements TrendsRepository {
  FirestoreTrendsRepository(this._db);

  final FirebaseFirestore _db;

  @override
  Stream<List<VitalReading>> readingsSince(String patientId, DateTime from) => _db
      .collection(Collections.vitalReadings)
      .where('patientId', isEqualTo: patientId)
      .where('timestamp', isGreaterThanOrEqualTo: Timestamp.fromDate(from))
      .orderBy('timestamp', descending: true)
      .limit(2000)
      .snapshots()
      .map((s) => [for (final d in s.docs) VitalReading.fromFirestore(d.id, d.data())]);

  @override
  Stream<List<RiskScore>> riskHistory(String patientId, {int limit = 60}) => _db
      .collection(Collections.riskScores)
      .where('patientId', isEqualTo: patientId)
      .orderBy('generatedAt', descending: true)
      .limit(limit)
      .snapshots()
      .map((s) => [for (final d in s.docs) RiskScore.fromFirestore(d.id, d.data())]);
}
