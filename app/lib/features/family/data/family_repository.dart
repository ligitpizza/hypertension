import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/constants/enums.dart';
import '../../../shared/services/api/api_client.dart';

/// A `family_link_requests` document (D-06).
class LinkRequest {
  const LinkRequest({
    required this.id,
    required this.familyMemberId,
    required this.patientId,
    required this.status,
    this.familyMemberName = 'A family member',
    this.createdAt,
  });

  final String id;
  final String familyMemberId;

  /// D-62: copied at request time; the patient can't read an unlinked user's document.
  final String familyMemberName;
  final String patientId;

  /// pending | approved | rejected
  final String status;
  final DateTime? createdAt;

  bool get isPending => status == 'pending';

  factory LinkRequest.fromFirestore(String id, Map<String, dynamic> d) => LinkRequest(
    id: id,
    familyMemberId: d['familyMemberId'] as String? ?? '',
    patientId: d['patientId'] as String? ?? '',
    status: d['status'] as String? ?? 'pending',
    familyMemberName: d['familyMemberName'] as String? ?? 'A family member',
    createdAt: (d['createdAt'] as Timestamp?)?.toDate(),
  );
}

/// An `emergency_alerts` document (Table 4.2.3.17; D-62).
class EmergencyAlert {
  const EmergencyAlert({
    required this.id,
    required this.patientId,
    required this.familyMemberId,
    required this.trigger,
    required this.sentAt,
    this.lat,
    this.lng,
    this.patientPhone,
    this.locationUpdatedAt,
    this.acknowledgedAt,
  });

  final String id;
  final String patientId;
  final String familyMemberId;

  /// emergency_reading | critical_risk | sos | triage
  final String trigger;
  final DateTime sentAt;
  final double? lat;
  final double? lng;
  final String? patientPhone;
  final DateTime? locationUpdatedAt;
  final DateTime? acknowledgedAt;

  bool get hasLocation => lat != null && lng != null;
  bool get isAcknowledged => acknowledgedAt != null;
  DateTime get locationTime => locationUpdatedAt ?? sentAt;

  String get title => switch (trigger) {
    'emergency_reading' => 'Critical BP reading',
    'critical_risk' => 'Critical health risk',
    'sos' => 'SOS pressed',
    'triage' => 'Emergency symptoms reported',
    _ => 'Emergency alert',
  };

  factory EmergencyAlert.fromFirestore(String id, Map<String, dynamic> d) {
    final geo = d['gpsLocation'];
    return EmergencyAlert(
      id: id,
      patientId: d['patientId'] as String? ?? '',
      familyMemberId: d['familyMemberId'] as String? ?? '',
      trigger: d['trigger'] as String? ?? 'emergency_reading',
      sentAt: (d['sentAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      lat: geo is GeoPoint ? geo.latitude : null,
      lng: geo is GeoPoint ? geo.longitude : null,
      patientPhone: d['patientPhone'] as String?,
      locationUpdatedAt: (d['locationUpdatedAt'] as Timestamp?)?.toDate(),
      acknowledgedAt: (d['acknowledgedAt'] as Timestamp?)?.toDate(),
    );
  }
}

/// A person on the other side of a link (name only).
class LinkedPerson {
  const LinkedPerson(this.uid, this.name);

  final String uid;
  final String name;
}

/// FR-14.2: reads from Firestore under the rules, writes through FastAPI.
abstract interface class FamilyRepository {
  // ---- family member ----
  Stream<String?> linkedPatientId(String familyUid);

  Stream<LinkRequest?> myPendingRequest(String familyUid);

  Stream<LinkedPerson?> person(String uid);

  Stream<List<EmergencyAlert>> myAlerts(String familyUid);

  Future<void> requestLink(String code);

  Future<void> withdraw(String requestId);

  Future<void> unlink();

  Future<void> acknowledge(String alertId);

  // ---- patient ----
  Stream<List<LinkRequest>> pendingForPatient(String patientId);

  Stream<List<LinkedPerson>> linkedFamily(String patientId);

  Future<void> decide(String requestId, {required bool approve});

  Future<void> removeMember(String uid);

  /// Returns how many family members were alerted.
  Future<int> sos({Map<String, double>? location, bool notifyFamily = true});

  Future<int> openEmergencies();

  Future<void> updateLocation(Map<String, double> location);
}

class FirebaseFamilyRepository implements FamilyRepository {
  FirebaseFamilyRepository(this._db, this._api);

  final FirebaseFirestore _db;
  final ApiClient _api;

  CollectionReference<Map<String, dynamic>> get _users => _db.collection(Collections.users);
  CollectionReference<Map<String, dynamic>> get _requests =>
      _db.collection(Collections.familyLinkRequests);
  CollectionReference<Map<String, dynamic>> get _alerts =>
      _db.collection(Collections.emergencyAlerts);

  @override
  Stream<String?> linkedPatientId(String familyUid) =>
      _users.doc(familyUid).snapshots().map((d) => d.data()?['patientId'] as String?);

  @override
  Stream<LinkRequest?> myPendingRequest(String familyUid) => _requests
      .where('familyMemberId', isEqualTo: familyUid)
      .where('status', isEqualTo: 'pending')
      .snapshots()
      .map(
        (s) =>
            s.docs.isEmpty ? null : LinkRequest.fromFirestore(s.docs.first.id, s.docs.first.data()),
      );

  @override
  Stream<LinkedPerson?> person(String uid) => _users
      .doc(uid)
      .snapshots()
      .map((d) => d.exists ? LinkedPerson(uid, d.data()?['name'] as String? ?? 'Patient') : null);

  @override
  Stream<List<EmergencyAlert>> myAlerts(String familyUid) => _alerts
      .where('familyMemberId', isEqualTo: familyUid)
      .orderBy('sentAt', descending: true)
      .limit(20)
      .snapshots()
      .map((s) => [for (final d in s.docs) EmergencyAlert.fromFirestore(d.id, d.data())]);

  @override
  Future<void> requestLink(String code) => _api.requestFamilyLink(code);

  @override
  Future<void> withdraw(String requestId) => _api.withdrawFamilyLink(requestId);

  @override
  Future<void> unlink() => _api.unlinkFamily();

  @override
  Future<void> acknowledge(String alertId) => _api.acknowledgeEmergency(alertId);

  @override
  Stream<List<LinkRequest>> pendingForPatient(String patientId) => _requests
      .where('patientId', isEqualTo: patientId)
      .where('status', isEqualTo: 'pending')
      .snapshots()
      .map((s) => [for (final d in s.docs) LinkRequest.fromFirestore(d.id, d.data())]);

  @override
  Stream<List<LinkedPerson>> linkedFamily(String patientId) => _users
      .where('role', isEqualTo: UserRole.familyMember.value)
      .where('patientId', isEqualTo: patientId)
      .snapshots()
      .map(
        (s) => [
          for (final d in s.docs)
            LinkedPerson(d.id, d.data()['name'] as String? ?? 'Family member'),
        ],
      );

  @override
  Future<void> decide(String requestId, {required bool approve}) =>
      _api.decideFamilyLink(requestId, approve: approve);

  @override
  Future<void> removeMember(String uid) => _api.removeFamilyMember(uid);

  @override
  Future<int> sos({Map<String, double>? location, bool notifyFamily = true}) async =>
      ((await _api.sos(location: location, notifyFamily: notifyFamily))['familyAlerted'] as num?)
          ?.toInt() ??
      0;

  @override
  Future<int> openEmergencies() async =>
      ((await _api.openEmergencies())['open'] as num?)?.toInt() ?? 0;

  @override
  Future<void> updateLocation(Map<String, double> location) =>
      _api.updateEmergencyLocation(location);
}
