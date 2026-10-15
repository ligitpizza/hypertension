import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/constants/enums.dart';
import '../../../shared/models/health_models.dart';
import '../../../shared/services/api/api_client.dart';

/// One bookable time (D-53).
class Slot {
  const Slot({required this.time, required this.period, required this.available});

  final DateTime time;

  /// morning | afternoon | evening (Fig 4.3.6.1 tabs).
  final String period;
  final bool available;
}

class DoctorInfo {
  const DoctorInfo({required this.id, required this.name, this.specialty});

  final String id;
  final String name;
  final String? specialty;

  factory DoctorInfo.fromJson(Map<String, dynamic> j) => DoctorInfo(
    id: '${j['id']}',
    name: j['name'] as String? ?? 'Your doctor',
    specialty: j['specialty'] as String?,
  );
}

class DaySlots {
  const DaySlots({required this.doctor, required this.slots, this.alternatives = const []});

  final DoctorInfo doctor;
  final List<Slot> slots;

  /// UC7.1 E1: nearest free times when this day has none.
  final List<DateTime> alternatives;
}

/// The patient has no doctor yet (D-54): offer "Request a doctor".
class NoDoctorException implements Exception {
  const NoDoctorException();
}

/// UC7.1 E1: the slot was just taken; [alternatives] are the nearest free ones.
class SlotTakenException implements Exception {
  const SlotTakenException(this.alternatives);

  final List<DateTime> alternatives;
}

/// D-56: the patient already has an active appointment; [message] names it.
class ActiveAppointmentException implements Exception {
  const ActiveAppointmentException(this.message);

  final String message;
}

/// D-54 request, as the patient / admin sees it.
class AssignmentRequest {
  const AssignmentRequest({
    required this.id,
    required this.patientId,
    required this.requestedBy,
    required this.kind,
    required this.status,
    required this.createdAt,
    this.proposedDoctorId,
    this.reason,
  });

  final String id;
  final String patientId;
  final String requestedBy;
  final AssignmentRequestKind kind;
  final AssignmentRequestStatus status;
  final DateTime createdAt;
  final String? proposedDoctorId;
  final String? reason;

  factory AssignmentRequest.fromFirestore(String id, Map<String, dynamic> d) => AssignmentRequest(
    id: id,
    patientId: d['patientId'] as String? ?? '',
    requestedBy: d['requestedBy'] as String? ?? '',
    kind: AssignmentRequestKind.fromValue(d['kind'] as String? ?? 'new_patient'),
    status: AssignmentRequestStatus.fromValue(d['status'] as String? ?? 'pending'),
    createdAt: (d['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    proposedDoctorId: d['proposedDoctorId'] as String?,
    reason: d['reason'] as String?,
  );
}

/// A doctor or patient name for lists (admin and calendar views).
class PersonName {
  const PersonName(this.uid, this.name, {this.role});

  final String uid;
  final String name;
  final String? role;
}

/// Module 7 data: reads from Firestore (rules), writes and slot logic through FastAPI.
abstract interface class AppointmentsRepository {
  /// The patient's appointments from [from] on (all statuses), soonest first.
  Stream<List<Appointment>> patientAppointments(String patientId, DateTime from);

  /// Past appointments, newest first (History).
  Stream<List<Appointment>> patientHistory(String patientId, DateTime before);

  /// The doctor's appointments in [start, end) (calendar).
  Stream<List<Appointment>> doctorAppointments(String doctorId, DateTime start, DateTime end);

  Future<DaySlots> slots(DateTime day);

  Future<String> book(DateTime time, AppointmentType type);

  /// D-55: ask the doctor to move it (the new time is held meanwhile).
  Future<void> requestReschedule(String id, DateTime time, String reason, {String? note});

  /// D-55: ask the doctor to cancel (applied at once within 2 hours of the visit).
  /// Returns true when it was cancelled immediately.
  Future<bool> requestCancel(String id, String reason, {String? note});

  Future<void> withdrawRequest(String id);

  /// D-55 (doctor or admin).
  Future<void> decide(String id, {required bool approve, String? note});

  Future<void> staffCancel(String id, String reason);

  /// D-56 (doctor or admin): [completed] or no-show.
  Future<void> recordOutcome(String id, {required bool completed});

  /// D-56: the patient's active appointments, past or future (one at a time).
  Stream<List<Appointment>> activeAppointments(String patientId);

  /// Admin overview: every doctor's appointments in [start, end).
  Stream<List<Appointment>> allAppointments(DateTime start, DateTime end);

  Future<Map<String, dynamic>> preVisitSummary(String appointmentId);

  // ---- D-54 ----
  Stream<List<AssignmentRequest>> myRequests(String patientId);

  Future<void> requestDoctor();

  Future<void> requestReassignment(String patientId, {String? proposedDoctorId, String? reason});

  Stream<List<AssignmentRequest>> pendingRequests();

  Future<void> approve(String requestId, String doctorId);

  Future<void> decline(String requestId, {String? reason});

  /// Active doctors (admin choosing who to assign; doctor proposing a colleague).
  Stream<List<PersonName>> doctors();

  Future<PersonName?> person(String uid);
}

class ApiAppointmentsRepository implements AppointmentsRepository {
  ApiAppointmentsRepository(this._db, this._api);

  final FirebaseFirestore _db;
  final ApiClient _api;

  CollectionReference<Map<String, dynamic>> get _appts => _db.collection(Collections.appointments);

  List<Appointment> _list(QuerySnapshot<Map<String, dynamic>> s) => [
    for (final d in s.docs) Appointment.fromFirestore(d.id, d.data()),
  ];

  @override
  Stream<List<Appointment>> patientAppointments(String patientId, DateTime from) => _appts
      .where('patientId', isEqualTo: patientId)
      .where('dateTime', isGreaterThanOrEqualTo: Timestamp.fromDate(from))
      .orderBy('dateTime')
      .snapshots()
      .map(_list);

  @override
  Stream<List<Appointment>> patientHistory(String patientId, DateTime before) => _appts
      .where('patientId', isEqualTo: patientId)
      .where('dateTime', isLessThan: Timestamp.fromDate(before))
      .orderBy('dateTime', descending: true)
      .limit(30)
      .snapshots()
      .map(_list);

  @override
  Stream<List<Appointment>> doctorAppointments(String doctorId, DateTime start, DateTime end) =>
      _appts
          .where('doctorId', isEqualTo: doctorId)
          .where('dateTime', isGreaterThanOrEqualTo: Timestamp.fromDate(start))
          .where('dateTime', isLessThan: Timestamp.fromDate(end))
          .orderBy('dateTime')
          .snapshots()
          .map(_list);

  static List<DateTime> _times(Object? raw) => [
    for (final t in (raw as List? ?? const [])) DateTime.parse('$t'),
  ];

  @override
  Future<DaySlots> slots(DateTime day) async {
    final iso =
        '${day.year}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}';
    try {
      final res = await _api.appointmentSlots(iso);
      return DaySlots(
        doctor: DoctorInfo.fromJson(Map<String, dynamic>.from(res['doctor'] as Map)),
        slots: [
          for (final s in (res['slots'] as List? ?? const []).cast<Map<dynamic, dynamic>>())
            Slot(
              time: DateTime.parse('${s['time']}'),
              period: '${s['period']}',
              available: s['available'] == true,
            ),
        ],
        alternatives: _times(res['alternatives']),
      );
    } on ApiException catch (e) {
      if (e.code == 'NO_DOCTOR') throw const NoDoctorException();
      rethrow;
    }
  }

  @override
  Future<String> book(DateTime time, AppointmentType type) async {
    try {
      return '${(await _api.bookAppointment(dateTime: time, type: type.value))['id']}';
    } on ApiException catch (e) {
      if (e.code == 'SLOT_TAKEN') {
        final d = e.details;
        throw SlotTakenException(_times(d is Map ? d['alternatives'] : null));
      }
      if (e.code == 'NO_DOCTOR') throw const NoDoctorException();
      if (e.code == 'ACTIVE_APPOINTMENT') throw ActiveAppointmentException(e.message);
      rethrow;
    }
  }

  @override
  Future<void> requestReschedule(String id, DateTime time, String reason, {String? note}) async {
    try {
      await _api.changeAppointment(id, dateTime: time, reason: reason, note: note);
    } on ApiException catch (e) {
      if (e.code == 'SLOT_TAKEN') throw const SlotTakenException([]);
      rethrow;
    }
  }

  @override
  Future<bool> requestCancel(String id, String reason, {String? note}) async =>
      (await _api.changeAppointment(id, cancel: true, reason: reason, note: note))['status'] ==
      AppointmentStatus.cancelled.value;

  @override
  Future<void> withdrawRequest(String id) => _api.changeAppointment(id, withdraw: true);

  @override
  Future<void> decide(String id, {required bool approve, String? note}) =>
      _api.decideAppointment(id, approve: approve, note: note);

  @override
  Future<void> staffCancel(String id, String reason) => _api.staffCancelAppointment(id, reason);

  @override
  Future<void> recordOutcome(String id, {required bool completed}) =>
      _api.recordAppointmentOutcome(id, completed ? 'completed' : 'no_show');

  @override
  Stream<List<Appointment>> activeAppointments(String patientId) => _appts
      .where('patientId', isEqualTo: patientId)
      .snapshots()
      .map(
        (s) => [
          for (final a in _list(s))
            if (a.isActive) a,
        ]..sort((a, b) => a.dateTime.compareTo(b.dateTime)),
      );

  @override
  Stream<List<Appointment>> allAppointments(DateTime start, DateTime end) => _appts
      .where('dateTime', isGreaterThanOrEqualTo: Timestamp.fromDate(start))
      .where('dateTime', isLessThan: Timestamp.fromDate(end))
      .orderBy('dateTime')
      .snapshots()
      .map(_list);

  @override
  Future<Map<String, dynamic>> preVisitSummary(String appointmentId) =>
      _api.preVisitSummary(appointmentId);

  @override
  Stream<List<AssignmentRequest>> myRequests(String patientId) => _db
      .collection(Collections.doctorAssignmentRequests)
      .where('patientId', isEqualTo: patientId)
      .snapshots()
      .map((s) => [for (final d in s.docs) AssignmentRequest.fromFirestore(d.id, d.data())]);

  @override
  Future<void> requestDoctor() => _api.requestDoctor();

  @override
  Future<void> requestReassignment(String patientId, {String? proposedDoctorId, String? reason}) =>
      _api.requestReassignment(patientId, proposedDoctorId: proposedDoctorId, reason: reason);

  @override
  Stream<List<AssignmentRequest>> pendingRequests() => _db
      .collection(Collections.doctorAssignmentRequests)
      .where('status', isEqualTo: AssignmentRequestStatus.pending.value)
      .orderBy('createdAt', descending: true)
      .snapshots()
      .map((s) => [for (final d in s.docs) AssignmentRequest.fromFirestore(d.id, d.data())]);

  @override
  Future<void> approve(String requestId, String doctorId) =>
      _api.approveAssignment(requestId, doctorId);

  @override
  Future<void> decline(String requestId, {String? reason}) =>
      _api.declineAssignment(requestId, reason: reason);

  @override
  Stream<List<PersonName>> doctors() => _db
      .collection(Collections.users)
      .where('role', isEqualTo: UserRole.doctor.value)
      .snapshots()
      .map(
        (s) => [
          for (final d in s.docs)
            if (d.data()['isActive'] != false)
              PersonName(d.id, d.data()['name'] as String? ?? 'Doctor', role: 'doctor'),
        ],
      );

  @override
  Future<PersonName?> person(String uid) async {
    final d = await _db.collection(Collections.users).doc(uid).get();
    final data = d.data();
    return data == null
        ? null
        : PersonName(uid, data['name'] as String? ?? 'Unknown', role: data['role'] as String?);
  }
}
