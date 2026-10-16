import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/enums.dart';
import '../../../shared/models/health_models.dart';
import '../../../shared/providers/api_providers.dart';
import '../../auth/state/auth_providers.dart';
import '../../dashboard/state/dashboard_providers.dart';
import '../data/portal_repository.dart';
import '../domain/portal_models.dart';

final portalRepositoryProvider = Provider<PortalRepository>(
  (ref) => FirestorePortalRepository(FirebaseFirestore.instance, ref.watch(apiClientProvider)),
);

Duration? _noRetry(int _, Object _) => null;

String? _doctorId(Ref ref) => ref.watch(authUidProvider).value;

/// UC8.1: the signed-in doctor's assigned patients (live).
final assignedPatientsProvider = StreamProvider<List<PortalPatient>>((ref) {
  final uid = _doctorId(ref);
  if (uid == null) return Stream.value(const []);
  return ref.watch(portalRepositoryProvider).assignedPatients(uid);
}, retry: _noRetry);

/// FR-8.4: open alerts addressed to this doctor (live, so new alerts appear at once).
final openAlertsProvider = StreamProvider<List<ClinicalAlert>>((ref) {
  final uid = _doctorId(ref);
  if (uid == null) return Stream.value(const []);
  return ref.watch(portalRepositoryProvider).openAlerts(uid);
}, retry: _noRetry);

// autoDispose: a listener that failed once (e.g. access changed during a reassignment)
// must start again when the doctor reopens the patient, not stay broken for the session.
final patientLatestReadingProvider = StreamProvider.autoDispose.family<VitalReading?, String>(
  (ref, patientId) => ref
      .watch(dashboardRepositoryProvider)
      .recentReadings(patientId, limit: 1)
      .map((r) => r.firstOrNull),
  retry: _noRetry,
);

final patientLatestRiskProvider = StreamProvider.autoDispose.family<RiskScore?, String>(
  (ref, patientId) => ref.watch(dashboardRepositoryProvider).latestRiskScore(patientId),
  retry: _noRetry,
);

/// Dashboard rows: each patient joined with their latest reading and risk score.
/// Rows fill in as each patient's data arrives. A patient with an open critical alert is
/// flagged as Emergency (D-37).
final patientRowsProvider = Provider.autoDispose<AsyncValue<List<PatientRow>>>((ref) {
  final emergencies = {
    for (final a in ref.watch(openAlertsProvider).value ?? const <ClinicalAlert>[])
      if (a.severity == RiskLevel.critical) a.patientId,
  };
  return ref
      .watch(assignedPatientsProvider)
      .whenData(
        (patients) => [
          for (final p in patients)
            PatientRow(
              patient: p,
              latestReading: ref.watch(patientLatestReadingProvider(p.uid)).value,
              latestRisk: ref.watch(patientLatestRiskProvider(p.uid)).value,
              emergency: emergencies.contains(p.uid),
            ),
        ],
      );
});

/// D-37: alert history for one patient on the doctor's patient page.
final patientAlertsProvider = StreamProvider.family<List<ClinicalAlert>, String>((ref, id) {
  final uid = _doctorId(ref);
  if (uid == null) return Stream.value(const []);
  return ref.watch(portalRepositoryProvider).patientAlerts(uid, id);
}, retry: _noRetry);

/// D-41: care plan versions for the doctor's editor.
final patientCarePlanHistoryProvider = StreamProvider.family<List<CarePlanVersion>, String>(
  (ref, id) => ref.watch(dashboardRepositoryProvider).carePlanHistory(id),
  retry: _noRetry,
);

final portalPatientProvider = StreamProvider.family<PortalPatient?, String>(
  (ref, id) => ref.watch(portalRepositoryProvider).patient(id),
  retry: _noRetry,
);

final patientReadingsProvider = StreamProvider.family<List<VitalReading>, String>(
  (ref, id) => ref.watch(dashboardRepositoryProvider).recentReadings(id, limit: 20),
  retry: _noRetry,
);

final patientMedicationsProvider = StreamProvider.family<List<Medication>, String>(
  (ref, id) => ref.watch(dashboardRepositoryProvider).medications(id),
  retry: _noRetry,
);

final patientNotesProvider = StreamProvider.family<List<ClinicalNote>, String>(
  (ref, id) => ref.watch(portalRepositoryProvider).notes(id),
  retry: _noRetry,
);

final patientPrescriptionsProvider = StreamProvider.family<List<Prescription>, String>(
  (ref, id) => ref.watch(portalRepositoryProvider).prescriptions(id),
  retry: _noRetry,
);

final patientCarePlanProvider = StreamProvider.family<CarePlan?, String>(
  (ref, id) => ref.watch(portalRepositoryProvider).carePlan(id),
  retry: _noRetry,
);

/// D-72 (M8): the patient's medication delivery preference.
final deliveryPreferenceProvider = FutureProvider.autoDispose.family<Map<String, dynamic>, String>(
  (ref, id) => ref.watch(portalRepositoryProvider).deliveryPreference(id),
);

/// D-44: computed by the API on demand (not stored); the card has its own Retry.
/// Recomputed when the patient logs a reading or changes their medicines, so an open
/// patient page never shows a stale comparison.
final medicationEffectProvider = FutureProvider.autoDispose.family<MedicationEffect, String>((
  ref,
  id,
) {
  ref.watch(patientLatestReadingProvider(id).select((r) => r.value?.id));
  ref.watch(
    patientMedicationsProvider(
      id,
    ).select((m) => m.value?.map((x) => '${x.id}:${x.schedule}').join()),
  );
  return ref.watch(portalRepositoryProvider).medicationEffect(id);
}, retry: (_, _) => null);
