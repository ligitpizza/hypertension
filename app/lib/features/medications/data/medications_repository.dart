import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/constants/enums.dart';
import '../../../shared/models/health_models.dart';
import '../../../shared/services/api/api_client.dart';
import '../../provider_portal/domain/portal_models.dart';

/// What the add / edit form sends (D-43 schedule format, D-05 stock fields).
class MedicationDraft {
  const MedicationDraft({
    required this.name,
    required this.dosage,
    required this.schedule,
    this.quantityOnHand,
    this.refillThresholdDays = 7,
  });

  final String name;
  final String dosage;
  final String schedule;
  final double? quantityOnHand;
  final int refillThresholdDays;

  Map<String, dynamic> toJson({bool acknowledgeWarnings = false}) => {
    'name': name,
    'dosage': dosage,
    'schedule': schedule,
    'quantityOnHand': ?quantityOnHand,
    'refillThresholdDays': refillThresholdDays,
    'acknowledgeWarnings': acknowledgeWarnings,
  };
}

/// UC5.1 E1 duplicates and UC5.6 interactions the patient must review before saving.
class MedicationWarnings implements Exception {
  const MedicationWarnings({required this.duplicates, required this.interactions});

  final List<String> duplicates;
  final List<InteractionWarning> interactions;

  factory MedicationWarnings.fromDetails(Object? details) {
    final d = details is Map ? details : const {};
    return MedicationWarnings(
      duplicates: [for (final x in (d['duplicates'] as List? ?? const [])) '$x'],
      interactions: InteractionWarning.fromDetails(d['interactions']),
    );
  }
}

/// Module 5: reads come from Firestore (rules: own data), writes go through FastAPI.
abstract interface class MedicationsRepository {
  /// dose_logs for one medication since [since] (UC5.3, UC5.5).
  Stream<List<DoseLog>> doseLogs(String medicationId, DateTime since);

  /// D-49: the doctor's prescriptions for this patient, newest first.
  Stream<List<Prescription>> prescriptions(String patientId);

  /// Add (id null) or edit. Throws [MedicationWarnings] until [acknowledge] is true.
  Future<void> save(MedicationDraft draft, {String? id, bool acknowledge = false});

  Future<void> delete(String id);

  /// Throws [ApiException] (e.g. DOSE_ALREADY_LOGGED). True when a missed dose was
  /// corrected as taken late (D-49).
  Future<bool> confirmDose(String medicationId, {DateTime? scheduledTime});
}

class ApiMedicationsRepository implements MedicationsRepository {
  ApiMedicationsRepository(this._db, this._api);

  final FirebaseFirestore _db;
  final ApiClient _api;

  @override
  Stream<List<DoseLog>> doseLogs(String medicationId, DateTime since) => _db
      .collection(Collections.doseLogs)
      .where('medicationId', isEqualTo: medicationId)
      .where('scheduledTime', isGreaterThanOrEqualTo: Timestamp.fromDate(since))
      .orderBy('scheduledTime', descending: true)
      .snapshots()
      .map((s) => [for (final d in s.docs) DoseLog.fromFirestore(d.id, d.data())]);

  @override
  Stream<List<Prescription>> prescriptions(String patientId) => _db
      .collection(Collections.prescriptions)
      .where('patientId', isEqualTo: patientId)
      .orderBy('issuedAt', descending: true)
      .limit(50)
      .snapshots()
      .map((s) => [for (final d in s.docs) Prescription.fromFirestore(d.id, d.data())]);

  @override
  Future<void> save(MedicationDraft draft, {String? id, bool acknowledge = false}) async {
    final body = draft.toJson(acknowledgeWarnings: acknowledge);
    try {
      id == null ? await _api.addMedication(body) : await _api.updateMedication(id, body);
    } on ApiException catch (e) {
      if (e.code == 'MEDICATION_WARNINGS') throw MedicationWarnings.fromDetails(e.details);
      rethrow;
    }
  }

  @override
  Future<void> delete(String id) => _api.deleteMedication(id);

  @override
  Future<bool> confirmDose(String medicationId, {DateTime? scheduledTime}) async =>
      (await _api.confirmDose(medicationId, scheduledTime: scheduledTime))['late'] == true;
}
