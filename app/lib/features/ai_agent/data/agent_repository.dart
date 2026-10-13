import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/constants/enums.dart';
import '../../../shared/services/api/api_client.dart';

/// One `agent_messages` document (Table 4.2.3.16).
class AgentMessage {
  const AgentMessage({
    required this.id,
    required this.fromPatient,
    required this.text,
    this.sentAt,
  });

  final String id;
  final bool fromPatient;
  final String text;

  /// Null for a moment after sending (server timestamp pending).
  final DateTime? sentAt;

  factory AgentMessage.fromFirestore(String id, Map<String, dynamic> d) => AgentMessage(
    id: id,
    fromPatient: d['role'] == 'patient',
    text: d['text'] as String? ?? '',
    sentAt: (d['sentAt'] as Timestamp?)?.toDate(),
  );
}

class AgentReply {
  const AgentReply({required this.reply, this.emergency = false, this.fallback = false});

  final String reply;

  /// UC-14.1.3: dangerous message; the doctor was alerted and the UI shows the 999 card.
  final bool emergency;

  /// UC2.6 E1: Gemini failed; the reply is the fallback text (not saved).
  final bool fallback;

  factory AgentReply.fromApi(Map<String, dynamic> j) => AgentReply(
    reply: j['reply'] as String? ?? '',
    emergency: j['emergency'] as bool? ?? false,
    fallback: j['fallback'] as bool? ?? false,
  );
}

/// UC2.7 action buttons, chosen by the server from the risk level (docs/06 §G).
enum AgentAction {
  bookAppointment('book_appointment'),
  viewMedications('view_medications'),
  bookEmergencyAppointment('book_emergency_appointment'),
  callEmergencyContact('call_emergency_contact'),
  alertFamily('alert_family');

  const AgentAction(this.value);
  final String value;

  static AgentAction? tryParse(String v) => values.where((a) => a.value == v).firstOrNull;
}

class ProactiveUpdate {
  const ProactiveUpdate({
    required this.text,
    this.riskLevel,
    this.actions = const [],
    this.fallback = false,
  });

  final String text;
  final RiskLevel? riskLevel;
  final List<AgentAction> actions;
  final bool fallback;

  factory ProactiveUpdate.fromApi(Map<String, dynamic> j) => ProactiveUpdate(
    text: j['text'] as String? ?? '',
    riskLevel: j['riskLevel'] == null ? null : RiskLevel.fromValue(j['riskLevel'] as String),
    actions: [
      for (final a in j['actions'] as List<dynamic>? ?? const [])
        ?AgentAction.tryParse(a as String),
    ],
    fallback: j['fallback'] as bool? ?? false,
  );
}

/// FR-14.1 (Fig 4.1.1.16 AIHealthAgentController). History is a live Firestore read;
/// questions go through FastAPI, which calls Gemini and saves both messages.
abstract interface class AgentRepository {
  Stream<List<AgentMessage>> messages(String patientId);

  Future<AgentReply> send(String message);

  Future<ProactiveUpdate> proactive();
}

class ApiAgentRepository implements AgentRepository {
  ApiAgentRepository(this._db, this._api);

  final FirebaseFirestore _db;
  final ApiClient _api;

  @override
  Stream<List<AgentMessage>> messages(String patientId) => _db
      .collection(Collections.agentMessages)
      .where('patientId', isEqualTo: patientId)
      .orderBy('sentAt')
      .limitToLast(100)
      .snapshots()
      .map((s) => [for (final d in s.docs) AgentMessage.fromFirestore(d.id, d.data())]);

  @override
  Future<AgentReply> send(String message) async =>
      AgentReply.fromApi(await _api.agentChat(message));

  @override
  Future<ProactiveUpdate> proactive() async => ProactiveUpdate.fromApi(await _api.agentProactive());
}
