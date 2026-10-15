import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/models/health_models.dart';
import '../../../shared/providers/api_providers.dart';
import '../../auth/state/auth_providers.dart';
import '../../dashboard/state/dashboard_providers.dart';
import '../data/appointments_repository.dart';

Duration? _noRetry(int _, Object _) => null;

final appointmentsRepositoryProvider = Provider<AppointmentsRepository>(
  (ref) => ApiAppointmentsRepository(FirebaseFirestore.instance, ref.watch(apiClientProvider)),
);

/// The patient's appointments from now on (all statuses; the page filters).
final myUpcomingAppointmentsProvider = StreamProvider<List<Appointment>>((ref) {
  final uid = ref.watch(authUidProvider).value;
  if (uid == null) return Stream.value(const []);
  // Start of today so a just-passed appointment still shows until the job completes it.
  final now = ref.watch(nowProvider)();
  return ref
      .watch(appointmentsRepositoryProvider)
      .patientAppointments(uid, DateTime(now.year, now.month, now.day));
}, retry: _noRetry);

final myAppointmentHistoryProvider = StreamProvider.autoDispose<List<Appointment>>((ref) {
  final uid = ref.watch(authUidProvider).value;
  if (uid == null) return Stream.value(const []);
  return ref.watch(appointmentsRepositoryProvider).patientHistory(uid, ref.watch(nowProvider)());
}, retry: _noRetry);

/// Slots for one Malaysian date (keyed by midnight of that date).
final daySlotsProvider = FutureProvider.autoDispose.family<DaySlots, DateTime>(
  (ref, day) => ref.watch(appointmentsRepositoryProvider).slots(day),
  retry: _noRetry,
);

final preVisitSummaryProvider = FutureProvider.autoDispose.family<Map<String, dynamic>, String>(
  (ref, id) => ref.watch(appointmentsRepositoryProvider).preVisitSummary(id),
  retry: _noRetry,
);

/// D-54: the signed-in patient's doctor requests.
final myAssignmentRequestsProvider = StreamProvider.autoDispose<List<AssignmentRequest>>((ref) {
  final uid = ref.watch(authUidProvider).value;
  if (uid == null) return Stream.value(const []);
  return ref.watch(appointmentsRepositoryProvider).myRequests(uid);
}, retry: _noRetry);

final personProvider = FutureProvider.family<PersonName?, String>(
  (ref, uid) => ref.watch(appointmentsRepositoryProvider).person(uid),
  retry: _noRetry,
);

final doctorsProvider = StreamProvider.autoDispose<List<PersonName>>(
  (ref) => ref.watch(appointmentsRepositoryProvider).doctors(),
  retry: _noRetry,
);

final pendingAssignmentRequestsProvider = StreamProvider.autoDispose<List<AssignmentRequest>>(
  (ref) => ref.watch(appointmentsRepositoryProvider).pendingRequests(),
  retry: _noRetry,
);

/// (doctorId, start, end) -> the doctor's appointments in that range (calendar).
final doctorAppointmentsProvider = StreamProvider.autoDispose
    .family<List<Appointment>, (String, DateTime, DateTime)>(
      (ref, k) => ref.watch(appointmentsRepositoryProvider).doctorAppointments(k.$1, k.$2, k.$3),
      retry: _noRetry,
    );

/// (start, end) -> all appointments (admin overview, D-55).
final allAppointmentsProvider = StreamProvider.autoDispose
    .family<List<Appointment>, (DateTime, DateTime)>(
      (ref, k) => ref.watch(appointmentsRepositoryProvider).allAppointments(k.$1, k.$2),
      retry: _noRetry,
    );
