import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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

final patientLatestReadingProvider = StreamProvider.family<VitalReading?, String>(
  (ref, patientId) => ref
      .watch(dashboardRepositoryProvider)
      .recentReadings(patientId, limit: 1)
      .map((r) => r.firstOrNull),
  retry: _noRetry,
);

final patientLatestRiskProvider = StreamProvider.family<RiskScore?, String>(
  (ref, patientId) => ref.watch(dashboardRepositoryProvider).latestRiskScore(patientId),
  retry: _noRetry,
);

/// Dashboard rows: each patient joined with their latest reading and risk score.
/// Rows fill in as each patient's data arrives.
final patientRowsProvider = Provider<AsyncValue<List<PatientRow>>>((ref) {
  return ref
      .watch(assignedPatientsProvider)
      .whenData(
        (patients) => [
          for (final p in patients)
            PatientRow(
              patient: p,
              latestReading: ref.watch(patientLatestReadingProvider(p.uid)).value,
              latestRisk: ref.watch(patientLatestRiskProvider(p.uid)).value,
            ),
        ],
      );
});

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
