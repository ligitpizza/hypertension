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
  static const doctorAssignmentRequests = 'doctor_assignment_requests';
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
  static const clinicalAlerts = 'clinical_alerts'; // D-32
  static const medicationStock = 'medication_stock'; // D-66
  static const medicationCatalog = 'medication_catalog'; // D-69
  static const pharmacyMessages = 'pharmacy_messages'; // D-69
  static const conversations = 'conversations'; // D-76
  static const conversationMessages = 'conversation_messages'; // D-76
  static const notifications = 'notifications'; // D-77

  static const all = [
    users,
    healthProfiles,
    vitalReadings,
    riskScores,
    triageOutcomes,
    medications,
    doseLogs,
    healthRecords,
    appointments,
    doctorAssignmentRequests,
    clinicalNotes,
    prescriptions,
    carePlans,
    messages,
    medicationOrders,
    auditLogs,
    agentMessages,
    emergencyAlerts,
    symptomCatalog,
    paymentTransactions,
    deliveryTrackingEvents,
    familyLinkRequests,
    clinicalAlerts,
    medicationStock,
    medicationCatalog,
    pharmacyMessages,
    conversations,
    conversationMessages,
    notifications,
  ];
}

/// Looks up an enum constant by its stored string value.
T enumFromValue<T extends Enum>(List<T> values, String value, String Function(T) toValue) =>
    values.firstWhere(
      (e) => toValue(e) == value,
      orElse: () => throw ArgumentError.value(value, 'value', 'Unknown ${T.toString()}'),
    );

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
  completed('completed'),
  noShow('no_show'); // D-56

  const AppointmentStatus(this.value);
  final String value;

  String get label => switch (this) {
    booked => 'booked',
    rescheduled => 'rescheduled',
    cancelled => 'cancelled',
    completed => 'completed',
    noShow => 'no-show',
  };
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

/// Patient gender (users.gender, D-25).
enum Gender {
  male('male'),
  female('female'),
  other('other');

  const Gender(this.value);
  final String value;
  static Gender fromValue(String v) => enumFromValue(values, v, (e) => e.value);
}

enum SmokingStatus {
  never('never'),
  former('former'),
  current('current');

  const SmokingStatus(this.value);
  final String value;
  static SmokingStatus fromValue(String v) => enumFromValue(values, v, (e) => e.value);
}

enum AlcoholUse {
  none('none'),
  occasional('occasional'),
  regular('regular');

  const AlcoholUse(this.value);
  final String value;
  static AlcoholUse fromValue(String v) => enumFromValue(values, v, (e) => e.value);
}

enum SaltIntake {
  low('low'),
  moderate('moderate'),
  high('high');

  const SaltIntake(this.value);
  final String value;
  static SaltIntake fromValue(String v) => enumFromValue(values, v, (e) => e.value);
}

/// Existing conditions captured at onboarding (D-25).
enum MedicalCondition {
  diabetes('diabetes'),
  chronicKidneyDisease('chronic_kidney_disease'),
  heartDisease('heart_disease'),
  heartFailure('heart_failure'),
  stroke('stroke'),
  highCholesterol('high_cholesterol');

  const MedicalCondition(this.value);
  final String value;
  static MedicalCondition fromValue(String v) => enumFromValue(values, v, (e) => e.value);
}

enum FamilyHistoryCondition {
  hypertension('hypertension'),
  heartDisease('heart_disease'),
  stroke('stroke'),
  diabetes('diabetes'),
  kidneyDisease('kidney_disease');

  const FamilyHistoryCondition(this.value);
  final String value;
  static FamilyHistoryCondition fromValue(String v) => enumFromValue(values, v, (e) => e.value);
}

/// Which client surface is calling the API (D-14).
enum ClientApp {
  patient('patient'),
  family('family'),
  staff('staff');

  const ClientApp(this.value);
  final String value;
  static ClientApp fromValue(String v) => enumFromValue(values, v, (e) => e.value);
}

enum SessionEvent {
  login('LOGIN'),
  logout('LOGOUT');

  const SessionEvent(this.value);
  final String value;
  static SessionEvent fromValue(String v) => enumFromValue(values, v, (e) => e.value);
}

/// Reasons recorded for failed sign-ins (D-27).
enum LoginFailureReason {
  invalidCredentials('invalid_credentials'),
  accountDeactivated('account_deactivated'),
  roleMismatch('role_mismatch'),
  wrongApp('wrong_app'),
  tooManyAttempts('too_many_attempts'),
  other('other');

  const LoginFailureReason(this.value);
  final String value;
  static LoginFailureReason fromValue(String v) => enumFromValue(values, v, (e) => e.value);
}

/// `clinical_alerts.type` (D-32).
enum ClinicalAlertType {
  threshold('threshold'),
  riskEscalation('risk_escalation'),
  deterioration('deterioration'),
  medicationReview('medication_review'),
  triage('triage'),
  flaggedMessage('flagged_message'),
  lowAdherence('low_adherence'); // D-49

  const ClinicalAlertType(this.value);
  final String value;
  static ClinicalAlertType fromValue(String v) => enumFromValue(values, v, (e) => e.value);
}

/// `clinical_alerts.status` (D-32).
enum ClinicalAlertStatus {
  open('open'),
  acknowledged('acknowledged'),
  dismissed('dismissed');

  const ClinicalAlertStatus(this.value);
  final String value;
  static ClinicalAlertStatus fromValue(String v) => enumFromValue(values, v, (e) => e.value);
}

/// `prescriptions.source` (D-50); absent means doctor.
enum PrescriptionSource {
  doctor('doctor'),
  patient('patient');

  const PrescriptionSource(this.value);
  final String value;
  static PrescriptionSource fromValue(String? v) =>
      v == null ? doctor : enumFromValue(values, v, (e) => e.value);
}

/// `appointments.type` (D-53); absent means checkup.
enum AppointmentType {
  checkup('checkup'),
  followUp('follow_up'),
  emergency('emergency');

  const AppointmentType(this.value);
  final String value;
  static AppointmentType fromValue(String? v) =>
      v == null ? checkup : enumFromValue(values, v, (e) => e.value);

  String get label => switch (this) {
    checkup => 'Regular checkup',
    followUp => 'Follow-up',
    emergency => 'Emergency',
  };
}

/// `doctor_assignment_requests.kind` (D-54).
enum AssignmentRequestKind {
  newPatient('new_patient'),
  reassign('reassign');

  const AssignmentRequestKind(this.value);
  final String value;
  static AssignmentRequestKind fromValue(String v) => enumFromValue(values, v, (e) => e.value);
}

/// `doctor_assignment_requests.status` (D-54).
enum AssignmentRequestStatus {
  pending('pending'),
  approved('approved'),
  declined('declined');

  const AssignmentRequestStatus(this.value);
  final String value;
  static AssignmentRequestStatus fromValue(String v) => enumFromValue(values, v, (e) => e.value);
}

/// health_records.category (D-58).
enum RecordCategory {
  labResult('lab_result', 'Lab result'),
  prescription('prescription', 'Prescription'),
  imaging('imaging', 'Imaging / scan'),
  dischargeSummary('discharge_summary', 'Discharge summary'),
  referralLetter('referral_letter', 'Referral letter'),
  other('other', 'Other');

  const RecordCategory(this.value, this.label);
  final String value;
  final String label;
  static RecordCategory fromValue(String v) => enumFromValue(values, v, (e) => e.value);
}
