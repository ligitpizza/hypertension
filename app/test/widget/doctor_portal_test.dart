import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hypertension/core/constants/enums.dart';
import 'package:hypertension/features/auth/state/auth_providers.dart';
import 'package:hypertension/features/charts/state/trends_providers.dart';
import 'package:hypertension/features/dashboard/data/dashboard_repository.dart';
import 'package:hypertension/features/dashboard/state/dashboard_providers.dart';
import 'package:hypertension/features/provider_portal/data/portal_repository.dart';
import 'package:hypertension/features/provider_portal/domain/portal_models.dart';
import 'package:hypertension/features/provider_portal/presentation/care_plan_page.dart';
import 'package:hypertension/features/provider_portal/presentation/clinical_note_page.dart';
import 'package:hypertension/features/provider_portal/presentation/doctor_dashboard_page.dart';
import 'package:hypertension/features/provider_portal/presentation/patient_detail_page.dart';
import 'package:hypertension/features/provider_portal/presentation/prescription_page.dart';
import 'package:hypertension/features/provider_portal/state/portal_providers.dart';
import 'package:hypertension/shared/models/health_models.dart';
import 'package:hypertension/shared/services/api/api_client.dart';

import '../helpers/fakes.dart';
import 'trends_page_test.dart' show FakeTrendsRepository;

// Module 8 doctor portal (FR-8.1-8.4; UC8.1-UC8.6; Figs 4.3.12.1-4.3.12.7).
final now = DateTime(2026, 10, 13, 12);

VitalReading reading(String p, int sys, int dia, {int hoursAgo = 1}) => VitalReading(
  id: 'r-$p-$sys',
  patientId: p,
  systolic: sys,
  diastolic: dia,
  timestamp: now.subtract(Duration(hours: hoursAgo)),
);

RiskScore risk(String p, RiskLevel level) => RiskScore(
  id: 's-$p',
  patientId: p,
  scores: {
    for (final c in Complication.values)
      c: ComplicationScore(value: c == Complication.stroke ? 0.31 : 0.002, level: RiskLevel.low),
    Complication.stroke: ComplicationScore(value: 0.31, level: level),
  },
  generatedAt: now,
  modelUsed: 'XGBoost v1',
);

/// Per-patient health data (the shared dashboard repository is reused by the portal).
class FakePatientData implements DashboardRepository {
  final Map<String, List<VitalReading>> readings = {};
  final Map<String, RiskScore> risks = {};
  final Map<String, List<Medication>> meds = {};

  @override
  Stream<List<VitalReading>> recentReadings(String patientId, {int limit = 20}) =>
      Stream.value((readings[patientId] ?? const []).take(limit).toList());

  @override
  Stream<RiskScore?> latestRiskScore(String patientId) => Stream.value(risks[patientId]);

  @override
  Stream<List<Medication>> medications(String patientId) =>
      Stream.value(meds[patientId] ?? const []);

  @override
  Stream<List<Appointment>> upcomingAppointments(String patientId, DateTime from) =>
      Stream.value(const []);
}

class FakePortalRepository implements PortalRepository {
  List<PortalPatient> patients = const [];
  List<ClinicalAlert> alerts = const [];
  List<ClinicalNote> notesList = const [];
  CarePlan? plan;
  final closed = <(String, ClinicalAlertStatus)>[];
  final addedNotes = <String>[];
  final savedPlans = <String>[];
  final rxCalls = <bool>[];
  List<Map<String, String>> interactionDetails = const [];

  @override
  Stream<List<PortalPatient>> assignedPatients(String doctorId) => Stream.value(patients);

  @override
  Stream<PortalPatient?> patient(String patientId) =>
      Stream.value(patients.where((p) => p.uid == patientId).firstOrNull);

  @override
  Stream<List<ClinicalAlert>> openAlerts(String doctorId) => Stream.value(alerts);

  @override
  Future<void> closeAlert(String alertId, ClinicalAlertStatus status) async =>
      closed.add((alertId, status));

  @override
  Stream<List<ClinicalNote>> notes(String patientId) => Stream.value(notesList);

  @override
  Stream<List<Prescription>> prescriptions(String patientId) => Stream.value(const []);

  @override
  Stream<CarePlan?> carePlan(String patientId) => Stream.value(plan);

  @override
  Future<void> addNote(String patientId, String content) async => addedNotes.add(content);

  @override
  Future<void> saveCarePlan(String patientId, String content) async => savedPlans.add(content);

  @override
  Future<String> issuePrescription(
    String patientId, {
    required String medicationName,
    required String dosage,
    required String frequency,
    String? duration,
    bool isRecurring = false,
    bool acknowledgeInteractions = false,
  }) async {
    rxCalls.add(acknowledgeInteractions);
    if (interactionDetails.isNotEmpty && !acknowledgeInteractions) {
      throw ApiException(
        'DRUG_INTERACTION',
        'Interaction',
        statusCode: 409,
        details: interactionDetails,
      );
    }
    return '$medicationName $dosage, $frequency';
  }
}

Widget portal(FakePortalRepository repo, FakePatientData data, String location) {
  final router = GoRouter(
    initialLocation: location,
    routes: [
      GoRoute(
        path: '/doctor',
        builder: (_, _) => const Scaffold(body: DoctorDashboardPage()),
        routes: [
          GoRoute(
            path: 'patient/:id',
            builder: (_, s) =>
                Scaffold(body: PatientDetailPage(patientId: s.pathParameters['id']!)),
            routes: [
              GoRoute(
                path: 'notes',
                builder: (_, s) =>
                    Scaffold(body: ClinicalNotePage(patientId: s.pathParameters['id']!)),
              ),
              GoRoute(
                path: 'prescriptions',
                builder: (_, s) =>
                    Scaffold(body: PrescriptionPage(patientId: s.pathParameters['id']!)),
              ),
              GoRoute(
                path: 'care-plan',
                builder: (_, s) => Scaffold(body: CarePlanPage(patientId: s.pathParameters['id']!)),
              ),
            ],
          ),
        ],
      ),
    ],
  );
  return ProviderScope(
    overrides: [
      portalRepositoryProvider.overrideWithValue(repo),
      dashboardRepositoryProvider.overrideWithValue(data),
      trendsRepositoryProvider.overrideWithValue(
        FakeTrendsRepository([for (final r in data.readings.values) ...r]),
      ),
      nowProvider.overrideWithValue(() => now),
      authUidProvider.overrideWith((ref) => Stream.value('u-doctor')),
    ],
    child: MaterialApp.router(routerConfig: router),
  );
}

void main() {
  late FakePortalRepository repo;
  late FakePatientData data;

  setUp(() {
    repo = FakePortalRepository()
      ..patients = const [
        PortalPatient(uid: 'p1', name: 'Siti Aminah', gender: 'female'),
        PortalPatient(uid: 'p2', name: 'Ali Hassan'),
        PortalPatient(uid: 'p3', name: 'Mei Lin'),
      ];
    data = FakePatientData()
      ..readings['p1'] = [reading('p1', 185, 112)]
      ..readings['p2'] = [reading('p2', 135, 85, hoursAgo: 3)]
      ..risks['p1'] = risk('p1', RiskLevel.critical)
      ..risks['p2'] = risk('p2', RiskLevel.moderate);
  });

  group('Fig 4.3.12.1 Doctor Dashboard', () {
    tallTest('UC8.1 lists assigned patients, highest risk first, with counts', (t) async {
      await t.pumpWidget(portal(repo, data, '/doctor'));
      await t.pumpAndSettle();
      final tiles = find.byType(ListTile);
      expect(
        [for (final e in tiles.evaluate()) ((e.widget as ListTile).title as Text).data],
        ['Siti Aminah', 'Ali Hassan', 'Mei Lin'],
      );
      expect(find.text('185/112'), findsOneWidget);
      expect(find.text('Critical Risk'), findsOneWidget);
      expect(find.text('No score yet'), findsOneWidget);
      expect(find.text('No readings yet'), findsOneWidget);
      expect(
        find.descendant(of: find.byKey(const Key('count-total')), matching: find.text('3')),
        findsOneWidget,
      );
    });

    tallTest('UC8.2 risk filter and A1 clear; search by name', (t) async {
      await t.pumpWidget(portal(repo, data, '/doctor'));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('filter-moderate')));
      await t.pump();
      expect(find.byKey(const Key('patient-p2')), findsOneWidget);
      expect(find.byKey(const Key('patient-p1')), findsNothing);
      await t.tap(find.byKey(const Key('filter-all')));
      await t.pump();
      expect(find.byKey(const Key('patient-p1')), findsOneWidget);
      await t.enterText(find.byKey(const Key('patient-search')), 'mei');
      await t.pump();
      expect(find.byKey(const Key('patient-p3')), findsOneWidget);
      expect(find.byKey(const Key('patient-p1')), findsNothing);
    });

    tallTest('UC8.1 E1 no assigned patients shows an empty state', (t) async {
      repo.patients = const [];
      await t.pumpWidget(portal(repo, data, '/doctor'));
      await t.pumpAndSettle();
      expect(find.text('No patients are assigned to you yet.'), findsOneWidget);
      expect(find.text('No open alerts.'), findsOneWidget);
    });

    tallTest('FR-8.4 alerts panel and Fig 4.3.12.2 critical banner; dismiss', (t) async {
      repo.alerts = [
        ClinicalAlert(
          id: 'a1',
          patientId: 'p1',
          type: ClinicalAlertType.threshold,
          severity: RiskLevel.critical,
          message: 'EMERGENCY: Siti Aminah logged 185/112 mmHg.',
          status: ClinicalAlertStatus.open,
          createdAt: now.subtract(const Duration(minutes: 10)),
        ),
        ClinicalAlert(
          id: 'a2',
          patientId: 'p2',
          type: ClinicalAlertType.riskEscalation,
          severity: RiskLevel.high,
          message: "Ali Hassan's risk rose to high.",
          status: ClinicalAlertStatus.open,
          createdAt: now,
        ),
      ];
      await t.pumpWidget(portal(repo, data, '/doctor'));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('critical-banner')), findsOneWidget);
      expect(find.text('CRITICAL: Siti Aminah'), findsOneWidget);
      expect(find.text('BP spike · Siti Aminah'), findsOneWidget);
      expect(find.text('10 min ago'), findsOneWidget);
      await t.tap(find.byKey(const Key('ack-a2')));
      await t.tap(find.byKey(const Key('banner-dismiss')));
      await t.pump();
      expect(repo.closed, [
        ('a2', ClinicalAlertStatus.acknowledged),
        ('a1', ClinicalAlertStatus.dismissed),
      ]);
    });

    tallTest('UC8.3 tapping a patient opens their record', (t) async {
      await t.pumpWidget(portal(repo, data, '/doctor'));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('patient-p1')));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('detail-latest-bp')), findsOneWidget);
    });
  });

  group('Fig 4.3.12.4 Patient Detail', () {
    tallTest('FR-8.2 shows latest vitals, risk breakdown and history tabs', (t) async {
      await t.pumpWidget(portal(repo, data, '/doctor/patient/p1'));
      await t.pumpAndSettle();
      expect(find.text('Siti Aminah'), findsOneWidget);
      expect(find.text('Female'), findsOneWidget);
      expect(find.text('185/112'), findsWidgets);
      expect(find.text('Critical Risk'), findsOneWidget);
      expect(find.text('31%'), findsOneWidget);
      expect(find.text('<1%'), findsNWidgets(4));
      expect(find.text('Clinical notes'), findsOneWidget);
    });

    tallTest('UC8.3 E1 a patient without history shows empty states', (t) async {
      await t.pumpWidget(portal(repo, data, '/doctor/patient/p3'));
      await t.pumpAndSettle();
      expect(find.text('No readings yet.'), findsOneWidget);
      expect(find.text('No risk score yet (needs three readings).'), findsOneWidget);
    });
  });

  group('Fig 4.3.12.5 Clinical note', () {
    tallTest('UC8.4 template fills the editor and Save stores the note', (t) async {
      await t.pumpWidget(portal(repo, data, '/doctor/patient/p1/notes'));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('note-save')));
      await t.pump();
      expect(find.text('Write the note before saving.'), findsOneWidget);
      await t.tap(find.byKey(const Key('template-SOAP Note')));
      await t.pump();
      expect(find.textContaining('S: \nO: \nA: \nP: '), findsOneWidget);
      await t.tap(find.byKey(const Key('note-save')));
      await t.pumpAndSettle();
      expect(repo.addedNotes, ['S: \nO: \nA: \nP:']);
      expect(find.byKey(const Key('note-saved')), findsOneWidget);
    });
  });

  group('Fig 4.3.12.7 Prescription', () {
    Future<void> fillForm(WidgetTester t) async {
      await t.enterText(find.byKey(const Key('rx-name')), 'Aliskiren');
      await t.enterText(find.byKey(const Key('rx-dosage')), '150mg');
      await t.tap(find.byKey(const Key('rx-frequency')));
      await t.pumpAndSettle();
      await t.tap(find.text('Once daily').last);
      await t.pumpAndSettle();
    }

    tallTest('UC8.4 issues a prescription', (t) async {
      await t.pumpWidget(portal(repo, data, '/doctor/patient/p1/prescriptions'));
      await t.pumpAndSettle();
      await fillForm(t);
      await t.tap(find.byKey(const Key('rx-submit')));
      await t.pumpAndSettle();
      expect(repo.rxCalls, [false]);
      expect(find.byKey(const Key('rx-saved')), findsOneWidget);
    });

    tallTest('UC8.4 E1 critical interaction needs review before prescribing', (t) async {
      repo.interactionDetails = const [
        {
          'newDrug': 'Aliskiren',
          'existingDrug': 'Lisinopril',
          'severity': 'critical',
          'message': 'Risk of kidney injury.',
        },
      ];
      await t.pumpWidget(portal(repo, data, '/doctor/patient/p1/prescriptions'));
      await t.pumpAndSettle();
      await fillForm(t);
      await t.tap(find.byKey(const Key('rx-submit')));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('interaction-dialog')), findsOneWidget);
      expect(find.text('With Lisinopril (critical)'), findsOneWidget);
      final proceed = find.byKey(const Key('interaction-proceed'));
      expect(t.widget<FilledButton>(proceed).onPressed, isNull);
      await t.tap(find.byKey(const Key('interaction-reviewed')));
      await t.pump();
      await t.tap(proceed);
      await t.pumpAndSettle();
      expect(repo.rxCalls, [false, true]);
      expect(find.byKey(const Key('rx-saved')), findsOneWidget);
    });

    tallTest('UC8.4 E1 cancelling the warning does not prescribe', (t) async {
      repo.interactionDetails = const [
        {'newDrug': 'x', 'existingDrug': 'Lisinopril', 'severity': 'major', 'message': 'm'},
      ];
      await t.pumpWidget(portal(repo, data, '/doctor/patient/p1/prescriptions'));
      await t.pumpAndSettle();
      await fillForm(t);
      await t.tap(find.byKey(const Key('rx-submit')));
      await t.pumpAndSettle();
      await t.tap(find.text('Cancel').last);
      await t.pumpAndSettle();
      expect(repo.rxCalls, [false]);
      expect(find.byKey(const Key('rx-saved')), findsNothing);
    });
  });

  group('UC8.5 Care plan', () {
    tallTest('loads the current plan and saves edits', (t) async {
      repo.plan = CarePlan(content: 'Target BP < 130/80', updatedAt: now);
      await t.pumpWidget(portal(repo, data, '/doctor/patient/p1/care-plan'));
      await t.pumpAndSettle();
      expect(find.text('Target BP < 130/80'), findsOneWidget);
      await t.enterText(find.byKey(const Key('care-plan-text')), 'Target BP < 130/80; low salt');
      await t.tap(find.byKey(const Key('care-plan-save')));
      await t.pumpAndSettle();
      expect(repo.savedPlans, ['Target BP < 130/80; low salt']);
      expect(find.byKey(const Key('care-plan-saved')), findsOneWidget);
    });
  });
}
