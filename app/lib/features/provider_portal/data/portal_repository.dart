import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/constants/enums.dart';
import '../../../shared/services/api/api_client.dart';
import '../domain/portal_models.dart';

/// Module 8 doctor portal data (Fig 4.1.1.8 ProviderCtrl).
///
/// Reads are Firestore listeners restricted by Security Rules to the doctor's own
/// assigned patients (FR-8.1, NFR-2.2). Clinical writes go through FastAPI, which
/// checks the assignment and audits them; acknowledging an alert is a direct
/// Firestore update the rules allow only for the addressed doctor (D-32).
abstract interface class PortalRepository {
  Stream<List<PortalPatient>> assignedPatients(String doctorId);

  Stream<PortalPatient?> patient(String patientId);

  Stream<List<ClinicalAlert>> openAlerts(String doctorId);

  /// All alerts (any status) this doctor received for one patient, newest first.
  Stream<List<ClinicalAlert>> patientAlerts(String doctorId, String patientId);

  Future<void> closeAlert(String alertId, ClinicalAlertStatus status);

  Stream<List<ClinicalNote>> notes(String patientId);

  Stream<List<Prescription>> prescriptions(String patientId);

  Stream<CarePlan?> carePlan(String patientId);

  Future<void> addNote(String patientId, String content);

  Future<void> saveCarePlan(String patientId, String content);

  /// Throws [ApiException] `DRUG_INTERACTION` with details until acknowledged (UC8.4 E1).
  Future<String> issuePrescription(
    String patientId, {
    required String medicationName,
    required String dosage,
    required String frequency,
    String? duration,
    bool isRecurring = false,
    bool acknowledgeInteractions = false,
  });

  /// D-44 risk before vs after starting medication.
  Future<MedicationEffect> medicationEffect(String patientId);

  /// D-50: the issuing doctor deletes their own prescription.
  Future<void> deletePrescription(String patientId, String prescriptionId);

  /// UC13.1: flag a prescription as a long-term monthly refill (or stop it).
  Future<void> setRecurring(String prescriptionId, bool recurring);
}

class FirestorePortalRepository implements PortalRepository {
  FirestorePortalRepository(this._db, this._api);

  final FirebaseFirestore _db;
  final ApiClient _api;

  @override
  Stream<List<PortalPatient>> assignedPatients(String doctorId) => _db
      .collection(Collections.users)
      .where('role', isEqualTo: UserRole.patient.value)
      .where('assignedDoctorId', isEqualTo: doctorId)
      .snapshots()
      .map((s) => [for (final d in s.docs) PortalPatient.fromFirestore(d.id, d.data())]);

  @override
  Stream<PortalPatient?> patient(String patientId) => _db
      .collection(Collections.users)
      .doc(patientId)
      .snapshots()
      .map((s) => s.exists ? PortalPatient.fromFirestore(s.id, s.data()!) : null);

  @override
  Stream<List<ClinicalAlert>> openAlerts(String doctorId) => _db
      .collection(Collections.clinicalAlerts)
      .where('doctorId', isEqualTo: doctorId)
      .where('status', isEqualTo: ClinicalAlertStatus.open.value)
      .orderBy('createdAt', descending: true)
      .limit(50)
      .snapshots()
      .map((s) => [for (final d in s.docs) ClinicalAlert.fromFirestore(d.id, d.data())]);

  @override
  Stream<List<ClinicalAlert>> patientAlerts(String doctorId, String patientId) => _db
      .collection(Collections.clinicalAlerts)
      .where('patientId', isEqualTo: patientId)
      .where('doctorId', isEqualTo: doctorId)
      .orderBy('createdAt', descending: true)
      .limit(50)
      .snapshots()
      .map((s) => [for (final d in s.docs) ClinicalAlert.fromFirestore(d.id, d.data())]);

  @override
  Future<void> closeAlert(String alertId, ClinicalAlertStatus status) => _db
      .collection(Collections.clinicalAlerts)
      .doc(alertId)
      .update({'status': status.value, 'acknowledgedAt': FieldValue.serverTimestamp()});

  @override
  Stream<List<ClinicalNote>> notes(String patientId) => _db
      .collection(Collections.clinicalNotes)
      .where('patientId', isEqualTo: patientId)
      .orderBy('createdAt', descending: true)
      .limit(50)
      .snapshots()
      .map((s) => [for (final d in s.docs) ClinicalNote.fromFirestore(d.id, d.data())]);

  @override
  Stream<List<Prescription>> prescriptions(String patientId) => _db
      .collection(Collections.prescriptions)
      .where('patientId', isEqualTo: patientId)
      .orderBy('issuedAt', descending: true)
      .limit(50)
      .snapshots()
      .map((s) => [for (final d in s.docs) Prescription.fromFirestore(d.id, d.data())]);

  @override
  Stream<CarePlan?> carePlan(String patientId) => _db
      .collection(Collections.carePlans)
      .doc(patientId)
      .snapshots()
      .map((s) => s.exists ? CarePlan.fromFirestore(s.data()!) : null);

  @override
  Future<void> addNote(String patientId, String content) =>
      _api.addClinicalNote(patientId, content);

  @override
  Future<void> saveCarePlan(String patientId, String content) =>
      _api.updateCarePlan(patientId, content);

  @override
  Future<String> issuePrescription(
    String patientId, {
    required String medicationName,
    required String dosage,
    required String frequency,
    String? duration,
    bool isRecurring = false,
    bool acknowledgeInteractions = false,
  }) async {
    final res = await _api.issuePrescription(
      patientId,
      medicationName: medicationName,
      dosage: dosage,
      frequency: frequency,
      duration: duration,
      isRecurring: isRecurring,
      acknowledgeInteractions: acknowledgeInteractions,
    );
    return res['medicationDetails'] as String? ?? medicationName;
  }

  @override
  Future<MedicationEffect> medicationEffect(String patientId) async =>
      MedicationEffect.fromJson(await _api.medicationEffect(patientId));

  @override
  Future<void> deletePrescription(String patientId, String prescriptionId) =>
      _api.deletePrescription(patientId, prescriptionId);

  @override
  Future<void> setRecurring(String prescriptionId, bool recurring) =>
      _api.setRecurring(prescriptionId, recurring);
}
