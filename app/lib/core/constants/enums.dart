// Shared enum values from docs/04-data-model.md.
// Must stay identical to docs/fixtures/enums.json and backend/app/core/enums.py
// (checked by test/unit/core/enums_test.dart).

/// Firestore collection names (Ch4 Table 4.2.3.x, plus D-06 family_link_requests).
abstract final class Collections {
  static const users = 'users';
  static const healthProfiles = 'health_profiles';
  static const vitalReadings = 'vital_readings';
  static const riskScores = 'risk_scores';
  static const triageOutcomes = 'triage_outcomes';
  static const medications = 'medications';
  static const doseLogs = 'dose_logs';
  static const healthRecords = 'health_records';
  static const appointments = 'appointments';
  static const clinicalNotes = 'clinical_notes';
  static const prescriptions = 'prescriptions';
  static const carePlans = 'care_plans';
  static const messages = 'messages';
  static const medicationOrders = 'medication_orders';
  static const auditLogs = 'audit_logs';
  static const agentMessages = 'agent_messages';
  static const emergencyAlerts = 'emergency_alerts';
  static const symptomCatalog = 'symptom_catalog';
  static const paymentTransactions = 'payment_transactions';
  static const deliveryTrackingEvents = 'delivery_tracking_events';
  static const familyLinkRequests = 'family_link_requests';

  static const all = [
    users, healthProfiles, vitalReadings, riskScores, triageOutcomes,
    medications, doseLogs, healthRecords, appointments, clinicalNotes,
    prescriptions, carePlans, messages, medicationOrders, auditLogs,
    agentMessages, emergencyAlerts, symptomCatalog, paymentTransactions,
    deliveryTrackingEvents, familyLinkRequests,
  ];
}

/// Looks up an enum constant by its stored string value.
T enumFromValue<T extends Enum>(List<T> values, String value, String Function(T) toValue) =>
    values.firstWhere((e) => toValue(e) == value,
        orElse: () => throw ArgumentError.value(value, 'value', 'Unknown ${T.toString()}'));

enum UserRole {
  patient('patient'),
  doctor('doctor'),
  pharmacist('pharmacist'),
  admin('admin'),
  familyMember('family_member');

  const UserRole(this.value);
  final String value;
  static UserRole fromValue(String v) => enumFromValue(values, v, (e) => e.value);
}

enum TriageSeverity {
  mild('mild'),
  moderate('moderate'),
  severe('severe');

  const TriageSeverity(this.value);
  final String value;
  static TriageSeverity fromValue(String v) => enumFromValue(values, v, (e) => e.value);
}

enum TriageOutcome {
  monitorAtHome('monitor_at_home'),
  contactDoctor('contact_doctor'),
  seekEmergencyCare('seek_emergency_care');

  const TriageOutcome(this.value);
  final String value;
  static TriageOutcome fromValue(String v) => enumFromValue(values, v, (e) => e.value);
}

enum DoseStatus {
  taken('taken'),
  missed('missed');

  const DoseStatus(this.value);
  final String value;
  static DoseStatus fromValue(String v) => enumFromValue(values, v, (e) => e.value);
}

enum AppointmentStatus {
  booked('booked'),
  rescheduled('rescheduled'),
  cancelled('cancelled'),
  completed('completed');

  const AppointmentStatus(this.value);
  final String value;
  static AppointmentStatus fromValue(String v) => enumFromValue(values, v, (e) => e.value);
}

enum OrderMethod {
  selfCollection('self_collection'),
  homeDelivery('home_delivery');

  const OrderMethod(this.value);
  final String value;
  static OrderMethod fromValue(String v) => enumFromValue(values, v, (e) => e.value);
}

enum PaymentStatus {
  pending('pending'),
  paid('paid'),
  failed('failed');

  const PaymentStatus(this.value);
  final String value;
  static PaymentStatus fromValue(String v) => enumFromValue(values, v, (e) => e.value);
}

/// `medication_orders.deliveryStatus` (current state only).
enum OrderDeliveryStatus {
  dispatched('dispatched'),
  inTransit('in_transit'),
  delivered('delivered'),
  failed('failed');

  const OrderDeliveryStatus(this.value);
  final String value;
  static OrderDeliveryStatus fromValue(String v) => enumFromValue(values, v, (e) => e.value);
}

/// `delivery_tracking_events.status` (full trail, includes picked_up).
enum TrackingEventStatus {
  dispatched('dispatched'),
  pickedUp('picked_up'),
  inTransit('in_transit'),
  delivered('delivered'),
  failed('failed');

  const TrackingEventStatus(this.value);
  final String value;
  static TrackingEventStatus fromValue(String v) => enumFromValue(values, v, (e) => e.value);
}

enum PaymentTransactionStatus {
  succeeded('succeeded'),
  failed('failed'),
  refunded('refunded');

  const PaymentTransactionStatus(this.value);
  final String value;
  static PaymentTransactionStatus fromValue(String v) => enumFromValue(values, v, (e) => e.value);
}

enum AgentMessageRole {
  patient('patient'),
  agent('agent');

  const AgentMessageRole(this.value);
  final String value;
  static AgentMessageRole fromValue(String v) => enumFromValue(values, v, (e) => e.value);
}

/// `family_link_requests.status` (D-06).
enum FamilyLinkStatus {
  pending('pending'),
  approved('approved'),
  rejected('rejected');

  const FamilyLinkStatus(this.value);
  final String value;
  static FamilyLinkStatus fromValue(String v) => enumFromValue(values, v, (e) => e.value);
}

/// Keys of the `risk_scores.scores` map (FR-9.2).
enum Complication {
  stroke('stroke'),
  cad('cad'),
  heartFailure('heartFailure'),
  ckd('ckd'),
  t2d('t2d');

  const Complication(this.value);
  final String value;
  static Complication fromValue(String v) => enumFromValue(values, v, (e) => e.value);
}

/// FR-9.3. Declared in ascending severity so the overall level is the max index (D-03).
enum RiskLevel {
  low('low'),
  moderate('moderate'),
  high('high'),
  critical('critical');

  const RiskLevel(this.value);
  final String value;
  static RiskLevel fromValue(String v) => enumFromValue(values, v, (e) => e.value);
}

/// BP classifier categories (docs/06 §E), ascending severity.
enum BpCategory {
  normal('normal'),
  elevated('elevated'),
  stage1('stage1'),
  stage2('stage2'),
  crisis('crisis');

  const BpCategory(this.value);
  final String value;
  static BpCategory fromValue(String v) => enumFromValue(values, v, (e) => e.value);
}

/// Threshold alert levels (FR-9.1, docs/06 §E). Kept separate from TriageOutcome (D-18).
enum AlertLevel {
  mild('mild'),
  moderate('moderate'),
  emergency('emergency');

  const AlertLevel(this.value);
  final String value;
  static AlertLevel fromValue(String v) => enumFromValue(values, v, (e) => e.value);
}

/// Drug interaction severity (docs/06 §C).
enum InteractionSeverity {
  minor('minor'),
  major('major'),
  critical('critical');

  const InteractionSeverity(this.value);
  final String value;
  static InteractionSeverity fromValue(String v) => enumFromValue(values, v, (e) => e.value);
}
