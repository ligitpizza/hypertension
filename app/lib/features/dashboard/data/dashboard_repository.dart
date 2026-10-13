import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/constants/enums.dart';
import '../../../shared/models/health_models.dart';

/// Reads for the patient dashboard (Fig 4.1.1.2 DashboardCtrl). All reads go
/// straight to Firestore through snapshot listeners (read/write split, NFR-1.1).
abstract interface class DashboardRepository {
  /// Most recent readings, newest first.
  Stream<List<VitalReading>> recentReadings(String patientId, {int limit = 20});

  /// Most recent risk score, or null if none has been generated yet (UC2.4 E1).
  Stream<RiskScore?> latestRiskScore(String patientId);

  /// The patient's medication list (today's plan, UC2.2).
  Stream<List<Medication>> medications(String patientId);

  /// The doctor's care plan for this patient, or null if none yet (Module 8, UC10.2 view).
  Stream<CarePlan?> carePlan(String patientId);

  /// D-41: every saved version of the care plan, newest first.
  Stream<List<CarePlanVersion>> carePlanHistory(String patientId);

  /// Upcoming appointments from [from], soonest first (UC2.3).
  Stream<List<Appointment>> upcomingAppointments(String patientId, DateTime from);
}

class FirestoreDashboardRepository implements DashboardRepository {
  FirestoreDashboardRepository(this._db);

  final FirebaseFirestore _db;

  @override
  Stream<List<VitalReading>> recentReadings(String patientId, {int limit = 20}) => _db
      .collection(Collections.vitalReadings)
      .where('patientId', isEqualTo: patientId)
      .orderBy('timestamp', descending: true)
      .limit(limit)
      .snapshots()
      .map((s) => [for (final d in s.docs) VitalReading.fromFirestore(d.id, d.data())]);

  @override
  Stream<RiskScore?> latestRiskScore(String patientId) => _db
      .collection(Collections.riskScores)
      .where('patientId', isEqualTo: patientId)
      .orderBy('generatedAt', descending: true)
      .limit(1)
      .snapshots()
      .map(
        (s) =>
            s.docs.isEmpty ? null : RiskScore.fromFirestore(s.docs.first.id, s.docs.first.data()),
      );

  @override
  Stream<List<Medication>> medications(String patientId) => _db
      .collection(Collections.medications)
      .where('patientId', isEqualTo: patientId)
      .snapshots()
      .map((s) => [for (final d in s.docs) Medication.fromFirestore(d.id, d.data())]);

  @override
  Stream<CarePlan?> carePlan(String patientId) => _db
      .collection(Collections.carePlans)
      .doc(patientId)
      .snapshots()
      .map((s) => s.exists ? CarePlan.fromFirestore(s.data()!) : null);

  @override
  Stream<List<CarePlanVersion>> carePlanHistory(String patientId) => _db
      .collection(Collections.carePlans)
      .doc(patientId)
      .collection('versions')
      .orderBy('savedAt', descending: true)
      .limit(50)
      .snapshots()
      .map((s) => [for (final d in s.docs) CarePlanVersion.fromFirestore(d.data())]);

  @override
  Stream<List<Appointment>> upcomingAppointments(String patientId, DateTime from) => _db
      .collection(Collections.appointments)
      .where('patientId', isEqualTo: patientId)
      .where('dateTime', isGreaterThanOrEqualTo: Timestamp.fromDate(from))
      .orderBy('dateTime')
      .limit(5)
      .snapshots()
      .map(
        (s) => [
          for (final d in s.docs) Appointment.fromFirestore(d.id, d.data()),
        ].where((a) => a.isActive).toList(),
      );
}
