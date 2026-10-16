import 'dart:async';

import 'package:flutter/material.dart';
import 'package:hypertension/features/medications/state/medication_providers.dart';
import 'package:hypertension/features/medications/data/medications_repository.dart';
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
import 'package:hypertension/features/symptom_checker/data/symptom_repository.dart';
import 'package:hypertension/features/symptom_checker/state/symptom_providers.dart';
import 'package:hypertension/shared/models/health_models.dart';
import 'package:hypertension/shared/services/api/api_client.dart';

import '../helpers/fakes.dart';
import 'symptom_checker_test.dart' show FakeSymptomRepository;
import 'trends_page_test.dart' show FakeTrendsRepository;
import 'package:hypertension/features/orders/state/orders_providers.dart';

import '../helpers/order_fakes.dart';

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
      c: ComplicationScore(
        value: c == Complication.stroke ? 0.31 : 0.002,
        level: RiskLevel.low,
        factors: const ['age'],
      ),
    Complication.stroke: ComplicationScore(
      value: 0.31,
      level: level,
      factors: const ['systolic', 'age', 'smoking'],
    ),
  },
  generatedAt: now,
  modelUsed: 'XGBoost v1',
);

/// Per-patient health data (the shared dashboard repository is reused by the portal).
class FakePatientData implements DashboardRepository {
  final Map<String, List<VitalReading>> readings = {};
  final Map<String, RiskScore> risks = {};
  final Map<String, List<Medication>> meds = {};

  /// When set, readings arrive live (a patient logging a new reading while the page is open).
  StreamController<List<VitalReading>>? live;

  @override
  Stream<List<VitalReading>> recentReadings(String patientId, {int limit = 20}) =>
      live?.stream.map((r) => r.take(limit).toList()) ??
      Stream.value((readings[patientId] ?? const []).take(limit).toList());

  @override
  Stream<RiskScore?> latestRiskScore(String patientId) => Stream.value(risks[patientId]);

  @override
  Stream<CarePlan?> carePlan(String patientId) => Stream.value(null);

  List<CarePlanVersion> versions = const [];

  @override
  Stream<List<CarePlanVersion>> carePlanHistory(String patientId) => Stream.value(versions);

  @override
  Stream<List<Medication>> medications(String patientId) =>
      Stream.value(meds[patientId] ?? const []);

  @override
  Stream<List<Appointment>> upcomingAppointments(String patientId, DateTime from) =>
      Stream.value(const []);
}

/// D-49 dose history reads dose_logs through the medications repository.
class FakeDoseLogs implements MedicationsRepository {
  final logs = <String, List<DoseLog>>{};

  @override
  Stream<List<DoseLog>> doseLogs(String medicationId, DateTime since) =>
      Stream.value(logs[medicationId] ?? const []);

  @override
  Stream<List<Prescription>> prescriptions(String patientId) => Stream.value(const []);

  @override
  Future<void> save(MedicationDraft draft, {String? id, bool acknowledge = false}) async {}

  @override
  Future<void> delete(String id) async {}

  @override
  Future<bool> confirmDose(String medicationId, {DateTime? scheduledTime}) async => false;

  @override
  Future<void> saveReportedPrescription(ReportedPrescription rx, {String? id}) async {}

  @override
  Future<void> deleteReportedPrescription(String id) async {}
}

final doseLogs = FakeDoseLogs();

class FakePortalRepository implements PortalRepository {
  final consolidated = <List<Map<String, dynamic>>>[];

  /// D-69: same interaction behaviour as [issuePrescription] (records rxCalls too).
  @override
  Future<({String details, double? total})> issueConsolidated(
    String patientId, {
    required List<Map<String, dynamic>> items,
    bool isRecurring = false,
    bool acknowledgeInteractions = false,
  }) async {
    final details = await issuePrescription(
      patientId,
      medicationName: '${items.first['catalogId']}',
      dosage: '${items.first['dose']}',
      frequency: '${items.first['frequency']}',
      isRecurring: isRecurring,
      acknowledgeInteractions: acknowledgeInteractions,
    );
    consolidated.add(items);
    return (details: details, total: 63.0);
  }

  final recurringCalls = <(String, bool)>[];

  @override
  Future<void> setRecurring(String prescriptionId, bool recurring) async =>
      recurringCalls.add((prescriptionId, recurring));

  List<PortalPatient> patients = const [];
  List<ClinicalAlert> alerts = const [];
  List<ClinicalNote> notesList = const [];
  CarePlan? plan;
  final closed = <(String, ClinicalAlertStatus)>[];
  final addedNotes = <String>[];
  final savedPlans = <String>[];
  final rxCalls = <bool>[];
  List<Map<String, String>> interactionDetails = const [];
  MedicationEffect effect = const MedicationEffect(status: 'no_medication');
  int effectCalls = 0;

  List<Prescription> rxList = const [];
  final deletedRx = <String>[];

  @override
  Future<void> deletePrescription(String patientId, String prescriptionId) async =>
      deletedRx.add(prescriptionId);

  @override
  Future<MedicationEffect> medicationEffect(String patientId) async {
    effectCalls++;
    return effect;
  }

  @override
  Stream<List<PortalPatient>> assignedPatients(String doctorId) => Stream.value(patients);

  @override
  Stream<PortalPatient?> patient(String patientId) =>
      Stream.value(patients.where((p) => p.uid == patientId).firstOrNull);

  @override
  Stream<List<ClinicalAlert>> openAlerts(String doctorId) => Stream.value(alerts);

  @override
  Stream<List<ClinicalAlert>> patientAlerts(String doctorId, String patientId) => Stream.value([
    for (final a in alerts)
      if (a.patientId == patientId) a,
  ]);

  @override
  Future<void> closeAlert(String alertId, ClinicalAlertStatus status) async =>
      closed.add((alertId, status));

  @override
  Stream<List<ClinicalNote>> notes(String patientId) => Stream.value(notesList);

  @override
  Stream<List<Prescription>> prescriptions(String patientId) => Stream.value(rxList);

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

final symptoms = FakeSymptomRepository();

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
      ordersRepositoryProvider.overrideWithValue(FakeOrdersRepository()), // D-69 catalogue
      medicationsRepositoryProvider.overrideWithValue(doseLogs),
      symptomRepositoryProvider.overrideWithValue(symptoms),
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

    tallTest('D-49 critical banner mentions poor adherence when that alert is open', (t) async {
      ClinicalAlert alert(String id, ClinicalAlertType type, RiskLevel level) => ClinicalAlert(
        id: id,
        patientId: 'p1',
        type: type,
        severity: level,
        message: type == ClinicalAlertType.lowAdherence
            ? 'Low medication adherence. Losartan 50mg: last 3 doses missed.'
            : 'EMERGENCY: Siti Aminah logged 185/112 mmHg.',
        status: ClinicalAlertStatus.open,
        createdAt: now,
      );
      repo.alerts = [alert('a1', ClinicalAlertType.threshold, RiskLevel.critical)];
      await t.pumpWidget(portal(repo, data, '/doctor'));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('banner-adherence')), findsNothing);
      repo.alerts = [
        alert('a1', ClinicalAlertType.threshold, RiskLevel.critical),
        alert('a3', ClinicalAlertType.lowAdherence, RiskLevel.moderate),
      ];
      await t.pumpWidget(Container());
      await t.pumpWidget(portal(repo, data, '/doctor'));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('banner-adherence')), findsOneWidget);
      expect(find.textContaining('Missed medication'), findsOneWidget);
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
      // D-40 contributing factors (Fig 4.3.12.4).
      expect(find.text('Raised by: Systolic BP, Age, Smoking'), findsOneWidget);
      expect(find.byKey(const Key('factors-cad')), findsNothing);
      // A Low complication is not explained even if old data carries factors.
      expect(find.textContaining('not proven causes'), findsOneWidget);
    });

    tallTest('UC8.3 E1 a patient without history shows empty states', (t) async {
      await t.pumpWidget(portal(repo, data, '/doctor/patient/p3'));
      await t.pumpAndSettle();
      expect(find.text('No readings yet.'), findsOneWidget);
      expect(find.text('No risk score yet (needs three readings).'), findsOneWidget);
    });
  });

  group('D-44 risk since starting medication', () {
    Future<void> openMeds(WidgetTester t) async {
      await t.pumpWidget(portal(repo, data, '/doctor/patient/p1'));
      await t.pumpAndSettle();
      await t.tap(find.text('Medications'));
      await t.pumpAndSettle();
    }

    tallTest('shows BP and per-complication risk before vs now', (t) async {
      repo.effect = MedicationEffect.fromJson({
        'status': 'ok',
        'firstMedication': 'Amlodipine 5mg',
        'startedAt': '2026-09-12T00:00:00Z',
        'daysOnMedication': 30,
        'early': false,
        'readingsBefore': 3,
        'readingsAfter': 3,
        'bpBefore': {'systolic': 162.3, 'diastolic': 99.0},
        'bpAfter': {'systolic': 131.7, 'diastolic': 83.0},
        'complications': {
          'stroke': {'before': 4.1, 'after': 2.6},
          'ckd': {'before': 12.0, 'after': 12.2},
          't2d': {'before': 5.0, 'after': 6.0},
        },
      });
      await openMeds(t);
      expect(find.text('Average BP: 162/99 → 132/83 mmHg'), findsOneWidget);
      expect(find.text('4.1% → 2.6%'), findsOneWidget);
      final stroke = find.byKey(const Key('effect-Previous stroke'));
      expect(
        find.descendant(of: stroke, matching: find.byIcon(Icons.arrow_downward)),
        findsOneWidget,
      );
      final ckd = find.byKey(const Key('effect-Kidney disease'));
      expect(find.descendant(of: ckd, matching: find.byIcon(Icons.remove)), findsOneWidget);
      expect(find.textContaining('Not proof that the medicine caused'), findsOneWidget);
      expect(find.byKey(const Key('effect-early')), findsNothing);
    });

    tallTest('a new reading while the page is open refreshes the comparison', (t) async {
      data.live = StreamController<List<VitalReading>>.broadcast();
      addTearDown(data.live!.close);
      await t.pumpWidget(portal(repo, data, '/doctor/patient/p1'));
      await t.pump();
      data.live!.add([reading('p1', 150, 95)]);
      await t.pumpAndSettle();
      await t.tap(find.text('Medications'));
      await t.pumpAndSettle();
      final before = repo.effectCalls;
      data.live!.add([reading('p1', 132, 84), reading('p1', 150, 95)]);
      await t.pumpAndSettle();
      expect(repo.effectCalls, greaterThan(before));
    });

    tallTest('D-49 doctor sees the last 14 days of each medicine', (t) async {
      final at = now.toUtc().subtract(const Duration(days: 1));
      data.meds['p1'] = const [
        Medication(id: 'm1', patientId: 'p1', name: 'Losartan', dosage: '50mg', schedule: '08:00'),
        Medication(
          id: 'm2',
          patientId: 'p1',
          name: 'Ibuprofen',
          dosage: '400mg',
          schedule: 'as_needed',
        ),
      ];
      doseLogs.logs
        ..['m1'] = [
          DoseLog(id: 'a', medicationId: 'm1', scheduledTime: at, status: 'missed'),
          DoseLog(
            id: 'b',
            medicationId: 'm1',
            scheduledTime: at.subtract(const Duration(days: 1)),
            status: 'taken',
            confirmedAt: at.subtract(const Duration(days: 1)).add(const Duration(hours: 3)),
          ),
          DoseLog(
            id: 'c',
            medicationId: 'm1',
            scheduledTime: at.subtract(const Duration(days: 2)),
            status: 'taken',
            confirmedAt: at.subtract(const Duration(days: 2)),
          ),
        ]
        ..['m2'] = [
          for (var i = 0; i < 4; i++)
            DoseLog(
              id: 'p$i',
              medicationId: 'm2',
              scheduledTime: at.subtract(Duration(hours: i)),
              status: 'taken',
              confirmedAt: at.subtract(Duration(hours: i)),
            ),
        ];
      addTearDown(() {
        data.meds.remove('p1');
        doseLogs.logs.clear();
      });
      await openMeds(t);
      expect(find.text('Last 14 days: 2 taken (1 late) · 1 missed'), findsOneWidget);
      expect(find.textContaining('taken 3 h late'), findsOneWidget);
      expect(find.textContaining(': missed'), findsOneWidget);
      expect(find.textContaining('As needed: taken 4× in the last 7 days'), findsOneWidget);
    });

    tallTest('explains why there is nothing to compare', (t) async {
      repo.effect = MedicationEffect.fromJson({
        'status': 'no_baseline',
        'firstMedication': 'Amlodipine 5mg',
        'startedAt': '2026-09-12T00:00:00Z',
        'daysOnMedication': 30,
      });
      await openMeds(t);
      expect(find.textContaining('no readings from before that date'), findsOneWidget);
    });

    tallTest('flags an early comparison', (t) async {
      repo.effect = MedicationEffect.fromJson({
        'status': 'model_unavailable',
        'firstMedication': 'Amlodipine 5mg',
        'startedAt': '2026-10-09T00:00:00Z',
        'daysOnMedication': 3,
        'early': true,
        'bpBefore': {'systolic': 150, 'diastolic': 95},
        'bpAfter': {'systolic': 145, 'diastolic': 92},
      });
      await openMeds(t);
      expect(find.byKey(const Key('effect-early')), findsOneWidget);
      expect(find.textContaining('showing BP only'), findsOneWidget);
    });
  });

  group('D-50 prescriptions in the portal', () {
    Prescription rx(
      String id, {
      String? doctorId,
      PrescriptionSource source = PrescriptionSource.doctor,
    }) => Prescription(
      id: id,
      medicationDetails: 'Med $id 5mg, Once daily',
      isRecurring: false,
      issuedAt: now,
      doctorId: doctorId,
      source: source,
    );

    tallTest('the issuing doctor can delete; others and patient-reported cannot', (t) async {
      repo.rxList = [
        rx('a', doctorId: 'u-doctor'),
        rx('b', doctorId: 'someone-else'),
        rx('c', source: PrescriptionSource.patient),
      ];
      addTearDown(() => repo.rxList = const []);
      await t.pumpWidget(portal(repo, data, '/doctor/patient/p1'));
      await t.pumpAndSettle();
      await t.tap(find.text('Medications'));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('rx-delete-a')), findsOneWidget);
      expect(find.byKey(const Key('rx-delete-b')), findsNothing);
      expect(find.byKey(const Key('rx-delete-c')), findsNothing);
      expect(find.text('Reported by patient'), findsOneWidget);
      await t.tap(find.byKey(const Key('rx-delete-a')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('rx-delete-confirm')));
      await t.pumpAndSettle();
      expect(repo.deletedRx, ['a']);
    });

    tallTest('UC13.1 the issuing doctor makes a prescription repeat monthly', (t) async {
      repo.rxList = [rx('a', doctorId: 'u-doctor'), rx('b', doctorId: 'someone-else')];
      addTearDown(() => repo.rxList = const []);
      await t.pumpWidget(portal(repo, data, '/doctor/patient/p1'));
      await t.pumpAndSettle();
      await t.tap(find.text('Medications'));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('rx-recurring-b')), findsNothing);
      await t.tap(find.byKey(const Key('rx-recurring-a')));
      await t.pumpAndSettle();
      expect(repo.recurringCalls, [('a', true)]);
      expect(find.textContaining('Repeats monthly'), findsOneWidget);
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
    /// D-69: medicines are picked from the catalogue.
    Future<void> fillForm(WidgetTester t) async {
      await t.enterText(find.byKey(const Key('rx-search')), 'aml');
      await t.pump();
      await t.tap(find.byKey(const Key('rx-option-amlodipine-5')));
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

    tallTest('D-69 consolidated prescription: several medicines, quantity and total', (t) async {
      await t.pumpWidget(portal(repo, data, '/doctor/patient/p1/prescriptions'));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('rx-submit')));
      await t.pump();
      expect(find.text('Add at least one medicine.'), findsOneWidget);
      await fillForm(t);
      await t.enterText(find.byKey(const Key('rx-search')), 'losartan');
      await t.pump();
      await t.tap(find.byKey(const Key('rx-option-losartan-50')));
      await t.pumpAndSettle();
      // 30 x RM0.30 + 30 x RM0.90 = RM36.00
      expect(find.text('Total RM36.00'), findsOneWidget);
      await t.tap(find.byKey(const Key('rx-frequency')).last);
      await t.pumpAndSettle();
      await t.tap(find.text('Twice daily').last);
      await t.pumpAndSettle();
      expect(find.text('Total RM63.00'), findsOneWidget); // quantity follows frequency (60)
      await t.tap(find.byKey(const Key('rx-recurring')));
      await t.tap(find.byKey(const Key('rx-submit')));
      await t.pumpAndSettle();
      expect(repo.consolidated.single, [
        {
          'catalogId': 'amlodipine-5',
          'dose': '1 tablet',
          'frequency': 'once_daily',
          'quantity': 30,
        },
        {
          'catalogId': 'losartan-50',
          'dose': '1 tablet',
          'frequency': 'twice_daily',
          'quantity': 60,
        },
      ]);
      expect(repo.rxCalls, [false]); // no interaction warning to acknowledge
      expect(find.textContaining('sent to the pharmacy'), findsOneWidget);
      expect(find.byKey(const Key('rx-empty')), findsOneWidget);
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

    tallTest('D-41 previous versions are listed under the editor', (t) async {
      data.versions = [
        CarePlanVersion(content: 'Target BP < 130/80', savedAt: now),
        CarePlanVersion(
          content: 'Walk 20 min daily',
          savedAt: now.subtract(const Duration(days: 2)),
        ),
      ];
      repo.plan = CarePlan(content: 'Target BP < 130/80', updatedAt: now);
      await t.pumpWidget(portal(repo, data, '/doctor/patient/p1/care-plan'));
      await t.pumpAndSettle();
      expect(find.text('Previous versions'), findsOneWidget);
      expect(find.text('Walk 20 min daily'), findsOneWidget);
      expect(find.text('Current'), findsOneWidget);
    });
  });

  group('D-37 emergency flag and history', () {
    ClinicalAlert critical(String patient) => ClinicalAlert(
      id: 'c-$patient',
      patientId: patient,
      type: ClinicalAlertType.threshold,
      severity: RiskLevel.critical,
      message: 'EMERGENCY: crisis reading.',
      status: ClinicalAlertStatus.open,
      createdAt: now,
    );

    tallTest('a patient with an open critical alert is flagged EMERGENCY and listed first', (
      t,
    ) async {
      repo.alerts = [critical('p3')]; // Mei Lin has no risk score but an emergency
      await t.pumpWidget(portal(repo, data, '/doctor'));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('emergency-p3')), findsOneWidget);
      expect(find.byKey(const Key('emergency-p1')), findsNothing);
      final tiles = find.byType(ListTile);
      expect(((tiles.evaluate().first.widget as ListTile).title as Text).data, 'Mei Lin');
    });

    tallTest('patient page shows alert and symptom-check history', (t) async {
      repo.alerts = [critical('p1')];
      symptoms.records = [
        TriageRecord(
          id: 'tr1',
          outcome: TriageOutcome.contactDoctor,
          severity: TriageSeverity.moderate,
          symptomIds: const ['dizziness'],
          generatedAt: now,
        ),
      ];
      await t.pumpWidget(portal(repo, data, '/doctor/patient/p1'));
      await t.pumpAndSettle();
      await t.tap(find.text('Alerts & triage'));
      await t.pumpAndSettle();
      expect(find.text('BP spike · critical'), findsOneWidget);
      expect(find.text('Contact doctor · moderate'), findsOneWidget);
      expect(find.textContaining('dizziness'), findsOneWidget);
      symptoms.records = const [];
    });
  });
}
