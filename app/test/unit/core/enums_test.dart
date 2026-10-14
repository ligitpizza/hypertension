import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hypertension/core/constants/enums.dart';

/// Dart enums must match docs/fixtures/enums.json (shared with the backend).
void main() {
  final fixture =
      jsonDecode(File('../docs/fixtures/enums.json').readAsStringSync()) as Map<String, dynamic>;
  List<String> expected(String key) => List<String>.from(fixture[key] as List);

  final cases = <String, List<String>>{
    'collections': Collections.all,
    'user_role': UserRole.values.map((e) => e.value).toList(),
    'triage_severity': TriageSeverity.values.map((e) => e.value).toList(),
    'triage_outcome': TriageOutcome.values.map((e) => e.value).toList(),
    'dose_status': DoseStatus.values.map((e) => e.value).toList(),
    'appointment_status': AppointmentStatus.values.map((e) => e.value).toList(),
    'order_method': OrderMethod.values.map((e) => e.value).toList(),
    'payment_status': PaymentStatus.values.map((e) => e.value).toList(),
    'order_delivery_status': OrderDeliveryStatus.values.map((e) => e.value).toList(),
    'tracking_event_status': TrackingEventStatus.values.map((e) => e.value).toList(),
    'payment_transaction_status': PaymentTransactionStatus.values.map((e) => e.value).toList(),
    'agent_message_role': AgentMessageRole.values.map((e) => e.value).toList(),
    'family_link_status': FamilyLinkStatus.values.map((e) => e.value).toList(),
    'complication': Complication.values.map((e) => e.value).toList(),
    'risk_level': RiskLevel.values.map((e) => e.value).toList(),
    'bp_category': BpCategory.values.map((e) => e.value).toList(),
    'alert_level': AlertLevel.values.map((e) => e.value).toList(),
    'interaction_severity': InteractionSeverity.values.map((e) => e.value).toList(),
    'gender': Gender.values.map((e) => e.value).toList(),
    'smoking_status': SmokingStatus.values.map((e) => e.value).toList(),
    'alcohol_use': AlcoholUse.values.map((e) => e.value).toList(),
    'salt_intake': SaltIntake.values.map((e) => e.value).toList(),
    'medical_condition': MedicalCondition.values.map((e) => e.value).toList(),
    'family_history_condition': FamilyHistoryCondition.values.map((e) => e.value).toList(),
    'client_app': ClientApp.values.map((e) => e.value).toList(),
    'session_event': SessionEvent.values.map((e) => e.value).toList(),
    'login_failure_reason': LoginFailureReason.values.map((e) => e.value).toList(),
    'clinical_alert_type': ClinicalAlertType.values.map((e) => e.value).toList(),
    'clinical_alert_status': ClinicalAlertStatus.values.map((e) => e.value).toList(),
    'prescription_source': PrescriptionSource.values.map((e) => e.value).toList(),
    'appointment_type': AppointmentType.values.map((e) => e.value).toList(),
    'assignment_request_kind': AssignmentRequestKind.values.map((e) => e.value).toList(),
    'assignment_request_status': AssignmentRequestStatus.values.map((e) => e.value).toList(),
  };

  for (final entry in cases.entries) {
    test('shared enum "${entry.key}" matches docs/fixtures/enums.json', () {
      expect(entry.value, expected(entry.key));
    });
  }

  test('fixture has no enum missing from the Dart constants', () {
    final keys = fixture.keys.where((k) => !k.startsWith('_')).toSet();
    expect(keys, cases.keys.toSet());
  });

  test('fromValue round-trips and rejects unknown values (FR-1.3 roles)', () {
    expect(UserRole.fromValue('family_member'), UserRole.familyMember);
    expect(() => UserRole.fromValue('superuser'), throwsArgumentError);
  });
}
