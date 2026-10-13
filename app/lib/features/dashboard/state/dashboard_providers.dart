import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/models/health_models.dart';
import '../../auth/state/auth_providers.dart';
import '../data/dashboard_repository.dart';

final dashboardRepositoryProvider = Provider<DashboardRepository>(
  (ref) => FirestoreDashboardRepository(FirebaseFirestore.instance),
);

/// Clock seam for tests.
final nowProvider = Provider<DateTime Function()>((ref) => DateTime.now);

Stream<T> _forUser<T>(Ref ref, Stream<T> Function(String uid) build, T empty) {
  final uid = ref.watch(authUidProvider).value;
  return uid == null ? Stream.value(empty) : build(uid);
}

// One provider per card, so a failing source only breaks its own card (UC2.1 E1).
// No automatic retry: the card shows the error with its own Retry button.
Duration? _noRetry(int _, Object _) => null;

final recentReadingsProvider = StreamProvider<List<VitalReading>>((ref) {
  final repo = ref.watch(dashboardRepositoryProvider);
  return _forUser(ref, (uid) => repo.recentReadings(uid), const <VitalReading>[]);
}, retry: _noRetry);

final latestRiskProvider = StreamProvider<RiskScore?>((ref) {
  final repo = ref.watch(dashboardRepositoryProvider);
  return _forUser<RiskScore?>(ref, repo.latestRiskScore, null);
}, retry: _noRetry);

final medicationsProvider = StreamProvider<List<Medication>>((ref) {
  final repo = ref.watch(dashboardRepositoryProvider);
  return _forUser(ref, repo.medications, const <Medication>[]);
}, retry: _noRetry);

/// The signed-in patient's care plan from their doctor (Module 2 "active care plan").
final carePlanProvider = StreamProvider<CarePlan?>((ref) {
  final repo = ref.watch(dashboardRepositoryProvider);
  return _forUser<CarePlan?>(ref, repo.carePlan, null);
}, retry: _noRetry);

final upcomingAppointmentsProvider = StreamProvider<List<Appointment>>((ref) {
  final repo = ref.watch(dashboardRepositoryProvider);
  final now = ref.watch(nowProvider)();
  final startOfToday = DateTime(now.year, now.month, now.day);
  return _forUser(
    ref,
    (uid) => repo.upcomingAppointments(uid, startOfToday),
    const <Appointment>[],
  );
}, retry: _noRetry);
