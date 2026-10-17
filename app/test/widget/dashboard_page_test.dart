import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hypertension/features/symptom_checker/data/symptom_repository.dart';
import 'package:hypertension/features/symptom_checker/state/symptom_providers.dart';
import 'package:hypertension/core/constants/enums.dart';
import 'package:hypertension/features/auth/domain/app_user.dart';
import 'package:hypertension/features/auth/state/auth_providers.dart';
import 'package:hypertension/features/dashboard/data/dashboard_repository.dart';
import 'package:hypertension/features/dashboard/presentation/dashboard_page.dart';
import 'package:hypertension/features/dashboard/presentation/patient_shell.dart';
import 'package:hypertension/features/dashboard/state/dashboard_providers.dart';
import 'package:hypertension/shared/models/health_models.dart';

import 'package:hypertension/features/notifications/data/notifications_repository.dart';
import 'package:hypertension/features/notifications/state/notification_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/fakes.dart';

var now = DateTime(2026, 10, 12, 9, 30);
String? doctorId;

class FakeDashboardRepository implements DashboardRepository {
  Stream<List<VitalReading>> readings = Stream.value(const []);
  Stream<RiskScore?> risk = Stream.value(null);
  Stream<List<Medication>> meds = Stream.value(const []);
  Stream<List<Appointment>> appts = Stream.value(const []);
  Stream<CarePlan?> plan = Stream.value(null);

  @override
  Stream<CarePlan?> carePlan(String patientId) => plan;

  Stream<List<CarePlanVersion>> history = Stream.value(const []);

  @override
  Stream<List<CarePlanVersion>> carePlanHistory(String patientId) => history;

  @override
  Stream<List<VitalReading>> recentReadings(String patientId, {int limit = 20}) => readings;

  @override
  Stream<RiskScore?> latestRiskScore(String patientId) => risk;

  @override
  Stream<List<Medication>> medications(String patientId) => meds;

  @override
  Stream<List<Appointment>> upcomingAppointments(String patientId, DateTime from) => appts;
}

TriageRecord? triage;
final dialed = <String>[];

Widget app(FakeDashboardRepository repo) {
  final router = GoRouter(
    initialLocation: '/dashboard',
    routes: [
      GoRoute(path: '/dashboard', builder: (_, _) => const DashboardPage()),
      for (final p in [
        '/vitals/log',
        '/symptom',
        '/chat',
        '/ai-agent',
        '/medications',
        '/appointments',
        '/notifications',
      ])
        GoRoute(
          path: p,
          builder: (_, s) => Text('ROUTE $p${s.extra == null ? '' : ' ${s.extra}'}'),
        ),
      GoRoute(
        path: '/chat/:id',
        builder: (_, s) => Text('ROUTE /chat/${s.pathParameters['id']} ${s.extra}'),
      ),
    ],
  );
  return ProviderScope(
    overrides: [
      dashboardRepositoryProvider.overrideWithValue(repo),
      latestTriageProvider.overrideWith((ref) => Stream.value(triage)),
      dialerProvider.overrideWithValue((n) async {
        dialed.add(n);
        return true;
      }),
      nowProvider.overrideWithValue(() => now),
      notificationInboxProvider.overrideWith((ref) async => const NotificationInbox([], 3)),
      authUidProvider.overrideWith((ref) => Stream.value('p1')),
      currentUserProvider.overrideWith(
        (ref) => Stream.value(
          AppUser(
            uid: 'p1',
            email: 's@x.my',
            name: 'Sarah Lim',
            role: UserRole.patient,
            isActive: true,
            onboardingComplete: true,
            assignedDoctorId: doctorId,
          ),
        ),
      ),
    ],
    child: MaterialApp.router(routerConfig: router),
  );
}

VitalReading reading(int sys, int dia, DateTime t, {int? hr}) => VitalReading(
  id: '$sys-$t',
  patientId: 'p1',
  systolic: sys,
  diastolic: dia,
  heartRate: hr,
  timestamp: t,
);

void main() {
  setUp(() {
    now = DateTime(2026, 10, 12, 9, 30);
    doctorId = null;
    SharedPreferences.setMockInitialValues({});
  });

  group('D-78 home', () {
    tallTest('crisis BP tints the card and warns; appointment tomorrow is called out', (t) async {
      final repo = FakeDashboardRepository()
        ..readings = Stream.value([reading(200, 150, now.subtract(const Duration(hours: 1)))])
        ..appts = Stream.value([
          Appointment(
            id: 'a',
            patientId: 'p1',
            dateTime: DateTime(2026, 10, 13, 10, 30),
            status: AppointmentStatus.booked,
          ),
        ]);
      await t.pumpWidget(app(repo));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('latest-bp-crisis')), findsOneWidget);
      expect(find.byKey(const Key('callout-appointment')), findsOneWidget);
      expect(find.textContaining("Don't forget"), findsOneWidget);
    });

    tallTest('no callouts when nothing needs attention', (t) async {
      await t.pumpWidget(app(FakeDashboardRepository()));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('callout-appointment')), findsNothing);
      expect(find.byKey(const Key('callout-order')), findsNothing);
    });
  });

  group('D-77 home', () {
    tallTest('the bell shows unread notifications and opens them', (t) async {
      await t.pumpWidget(app(FakeDashboardRepository()));
      await t.pumpAndSettle();
      expect(
        find.descendant(of: find.byKey(const Key('bell-badge')), matching: find.text('3')),
        findsOneWidget,
      );
      await t.tap(find.byKey(const Key('notification-bell')));
      await t.pumpAndSettle();
      expect(find.textContaining('ROUTE /notifications'), findsOneWidget);
    });

    tallTest('greeting and line follow the time of day', (t) async {
      now = DateTime(2026, 10, 12, 22, 30);
      await t.pumpWidget(app(FakeDashboardRepository()));
      await t.pumpAndSettle();
      expect(find.text('Good Night, Sarah'), findsOneWidget);
      expect(find.textContaining('Rest well'), findsOneWidget);
      expect(find.byKey(const Key('bp-nudge')), findsNothing); // only before noon
    });

    tallTest('morning nudge to log BP; Not now hides it for the day', (t) async {
      await t.pumpWidget(app(FakeDashboardRepository()));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('bp-nudge')), findsOneWidget);
      await t.tap(find.byKey(const Key('bp-nudge-later')));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('bp-nudge')), findsNothing);
      // Still hidden after a restart the same day.
      await t.pumpWidget(const SizedBox());
      await t.pumpWidget(app(FakeDashboardRepository()));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('bp-nudge')), findsNothing);
    });

    tallTest('no nudge once today is logged', (t) async {
      final repo = FakeDashboardRepository()
        ..readings = Stream.value([reading(128, 82, now.subtract(const Duration(hours: 1)))]);
      await t.pumpWidget(app(repo));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('bp-nudge')), findsNothing);
    });

    tallTest('tapping the risk card asks the AI Health Agent', (t) async {
      final repo = FakeDashboardRepository()
        ..risk = Stream.value(
          RiskScore(
            id: 'r1',
            patientId: 'p1',
            generatedAt: now,
            modelUsed: 'rf',
            scores: const {
              Complication.stroke: ComplicationScore(value: 0.4, level: RiskLevel.high),
            },
          ),
        );
      await t.pumpWidget(app(repo));
      await t.pumpAndSettle();
      await t.ensureVisible(find.byKey(const Key('risk-ask-agent')));
      await t.tap(find.byKey(const Key('risk-ask-agent')));
      await t.pumpAndSettle();
      expect(
        find.textContaining('ROUTE /ai-agent [Explain my highest complication risk'),
        findsOneWidget,
      );
    });

    tallTest('care plan: Ask my doctor opens the doctor chat with a draft', (t) async {
      doctorId = 'd1';
      final repo = FakeDashboardRepository()
        ..plan = Stream.value(CarePlan(content: 'Walk 30 minutes daily', updatedAt: now));
      await t.pumpWidget(app(repo));
      await t.pumpAndSettle();
      await t.ensureVisible(find.byKey(const Key('care-plan-ask-doctor')));
      await t.tap(find.byKey(const Key('care-plan-ask-doctor')));
      await t.pumpAndSettle();
      expect(find.textContaining('ROUTE /chat/d1 About my care plan'), findsOneWidget);
    });
  });

  tallTest('FR-2.1 UC2.2-2.4 empty states for a brand-new patient', (t) async {
    await t.pumpWidget(app(FakeDashboardRepository()));
    await t.pumpAndSettle();
    expect(find.text('Good Morning, Sarah'), findsOneWidget);
    expect(find.byKey(const Key('empty-medications')), findsOneWidget); // UC2.2 E1
    expect(find.byKey(const Key('empty-appointments')), findsOneWidget); // UC2.3 E1
    expect(find.byKey(const Key('empty-bp')), findsOneWidget);
    expect(find.byKey(const Key('empty-risk')), findsOneWidget); // UC2.4 E1
    expect(find.textContaining('Log 3 more blood pressure readings'), findsOneWidget);
  });

  tallTest('FR-2.1 shows plan, latest reading with change, and overall risk', (t) async {
    final repo = FakeDashboardRepository()
      ..meds = Stream.value(const [
        Medication(
          id: 'm',
          patientId: 'p1',
          name: 'Lisinopril',
          dosage: '10mg',
          schedule: 'Take with breakfast',
        ),
      ])
      ..appts = Stream.value([
        Appointment(
          id: 'a',
          patientId: 'p1',
          dateTime: DateTime(2026, 10, 13, 10, 30),
          status: AppointmentStatus.booked,
        ),
      ])
      ..readings = Stream.value([
        reading(128, 82, now.subtract(const Duration(hours: 2)), hr: 72),
        reading(132, 84, DateTime(2026, 10, 11, 20)),
        reading(135, 85, DateTime(2026, 10, 10, 20)),
      ])
      ..risk = Stream.value(
        RiskScore(
          id: 'r',
          patientId: 'p1',
          generatedAt: now,
          modelUsed: 'x',
          scores: const {
            Complication.stroke: ComplicationScore(value: 0.3, level: RiskLevel.moderate),
            Complication.cad: ComplicationScore(value: 0.1, level: RiskLevel.low),
          },
        ),
      );
    await t.pumpWidget(app(repo));
    await t.pumpAndSettle();
    expect(find.text('Lisinopril 10mg'), findsOneWidget);
    expect(find.text('Take with breakfast'), findsOneWidget);
    expect(find.text('Tomorrow, 10:30 AM'), findsOneWidget);
    expect(find.text('128 / 82  mmHg', findRichText: true), findsOneWidget);
    expect(find.text('2 hours ago'), findsOneWidget);
    expect(find.text('-4 from yesterday'), findsOneWidget);
    expect(find.text('Heart rate 72 bpm (estimate)'), findsOneWidget);
    expect(find.text('Moderate Risk'), findsOneWidget);
  });

  tallTest('UC2.1 E1 a failing section shows its own error; others still render', (t) async {
    final repo = FakeDashboardRepository()
      ..risk = Stream.error(Exception('permission-denied'))
      ..readings = Stream.value([reading(118, 76, now)]);
    await t.pumpWidget(app(repo));
    await t.pumpAndSettle();
    expect(find.text('Could not load your risk assessment.'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
    expect(find.text('118 / 76  mmHg', findRichText: true), findsOneWidget);
    expect(find.byKey(const Key('empty-medications')), findsOneWidget);
  });

  tallTest('loading state while data streams have not emitted', (t) async {
    final pending = StreamController<List<VitalReading>>();
    addTearDown(pending.close);
    final repo = FakeDashboardRepository()..readings = pending.stream;
    await t.pumpWidget(app(repo));
    await t.pump();
    expect(find.byType(CircularProgressIndicator), findsWidgets);
  });

  for (final (key, route) in [
    ('qa-vitals', '/vitals/log'),
    ('qa-symptoms', '/symptom'),
    ('qa-messages', '/chat'),
    ('qa-agent', '/ai-agent'),
    ('qa-appointments', '/appointments'),
  ]) {
    tallTest('FR-2.2 UC2.5 quick action $key opens $route', (t) async {
      await t.pumpWidget(app(FakeDashboardRepository()));
      await t.pumpAndSettle();
      await t.tap(find.byKey(Key(key)));
      await t.pumpAndSettle();
      expect(find.text('ROUTE $route'), findsOneWidget);
    });
  }

  testWidgets('quick actions sit four to a row on a phone', (t) async {
    t.view.physicalSize = const Size(360, 800);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(app(FakeDashboardRepository()));
    await t.pumpAndSettle();
    await t.scrollUntilVisible(
      find.byKey(const Key('qa-appointments')),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    final first = t.getTopLeft(find.byKey(const Key('qa-vitals')));
    final fourth = t.getTopLeft(find.byKey(const Key('qa-agent')));
    final fifth = t.getTopLeft(find.byKey(const Key('qa-appointments')));
    expect(fourth.dy, first.dy); // same row
    expect(fifth.dy, greaterThan(first.dy)); // wraps to the next row
    expect(fifth.dx, first.dx);
    expect(t.takeException(), isNull);
  });

  tallTest('patient shell highlights the current tab', (t) async {
    await t.pumpWidget(
      const MaterialApp(
        home: PatientShell(location: '/records', child: Text('BODY')),
      ),
    );
    final bar = t.widget<NavigationBar>(find.byType(NavigationBar));
    expect(bar.selectedIndex, 3);
    expect(find.text('Records'), findsOneWidget);
  });

  group('Android back navigation', () {
    Widget shellApp(String initial) {
      final router = GoRouter(
        initialLocation: initial,
        routes: [
          ShellRoute(
            builder: (_, s, child) => PatientShell(location: s.matchedLocation, child: child),
            routes: [
              GoRoute(path: '/dashboard', builder: (_, _) => const Text('HOME')),
              GoRoute(path: '/vitals', builder: (_, _) => const Text('VITALS TAB')),
            ],
          ),
          GoRoute(
            path: '/appointments',
            builder: (_, _) => const ComingSoonPage(title: 'Appointments', note: 'soon'),
          ),
        ],
      );
      return MaterialApp.router(routerConfig: router);
    }

    tallTest('back on a non-home tab returns to Home instead of leaving', (t) async {
      await t.pumpWidget(shellApp('/vitals'));
      await t.pumpAndSettle();
      expect(find.text('VITALS TAB'), findsOneWidget);
      await t.binding.handlePopRoute();
      await t.pumpAndSettle();
      expect(find.text('HOME'), findsOneWidget);
    });

    tallTest('pages opened from the dashboard have a back arrow to it', (t) async {
      await t.pumpWidget(shellApp('/dashboard'));
      await t.pumpAndSettle();
      GoRouter.of(t.element(find.text('HOME'))).push('/appointments');
      await t.pumpAndSettle();
      expect(find.byType(BackButton), findsOneWidget);
      await t.tap(find.byType(BackButton));
      await t.pumpAndSettle();
      expect(find.text('HOME'), findsOneWidget);
    });

    tallTest('"Log one" opens on top of the dashboard and back returns', (t) async {
      await t.pumpWidget(app(FakeDashboardRepository()));
      await t.pumpAndSettle();
      await t.tap(find.text('Log one'));
      await t.pumpAndSettle();
      expect(find.text('ROUTE /vitals/log'), findsOneWidget);
      await t.binding.handlePopRoute();
      await t.pumpAndSettle();
      expect(find.byKey(const Key('dashboard-greeting')), findsOneWidget);
    });
  });

  group('D-37 dashboard emergency call card', () {
    VitalReading reading(int sys, int dia, Duration ago) => VitalReading(
      id: 'r',
      patientId: 'p1',
      systolic: sys,
      diastolic: dia,
      timestamp: now.subtract(ago),
    );

    tearDown(() {
      triage = null;
      dialed.clear();
    });

    tallTest('crisis reading in the last 6 h shows Call 999, which opens the dialer', (t) async {
      final repo = FakeDashboardRepository()
        ..readings = Stream.value([reading(186, 122, const Duration(hours: 1))]);
      await t.pumpWidget(app(repo));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('dashboard-emergency')), findsOneWidget);
      await t.tap(find.byKey(const Key('dashboard-call-999')));
      await t.pump();
      expect(dialed, ['999']);
    });

    tallTest('emergency symptom check also shows it; normal readings do not', (t) async {
      triage = TriageRecord(
        id: 't',
        outcome: TriageOutcome.seekEmergencyCare,
        severity: TriageSeverity.severe,
        symptomIds: const ['chest_pain'],
        generatedAt: now.subtract(const Duration(minutes: 20)),
      );
      final repo = FakeDashboardRepository()
        ..readings = Stream.value([reading(118, 76, const Duration(minutes: 5))]);
      await t.pumpWidget(app(repo));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('dashboard-emergency')), findsOneWidget);
    });

    tallTest('no card without an active emergency', (t) async {
      final repo = FakeDashboardRepository()
        ..readings = Stream.value([reading(186, 122, const Duration(hours: 7))]);
      await t.pumpWidget(app(repo));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('dashboard-emergency')), findsNothing);
    });
  });

  group('Module 2 active care plan card', () {
    tallTest('shows an empty state before the doctor writes one', (t) async {
      await t.pumpWidget(app(FakeDashboardRepository()));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('care-plan-empty')), findsOneWidget);
    });

    tallTest('D-41 View history lists every version, newest marked Current', (t) async {
      final repo = FakeDashboardRepository()
        ..plan = Stream.value(CarePlan(content: 'Wake up early', updatedAt: now))
        ..history = Stream.value([
          CarePlanVersion(content: 'Wake up early', savedAt: now),
          CarePlanVersion(
            content: 'Drink more water today',
            savedAt: now.subtract(const Duration(days: 1)),
          ),
        ]);
      await t.pumpWidget(app(repo));
      await t.pumpAndSettle();
      await t.ensureVisible(find.byKey(const Key('care-plan-history-button')));
      await t.tap(find.byKey(const Key('care-plan-history-button')));
      await t.pumpAndSettle();
      expect(find.text('Care plan history'), findsOneWidget);
      expect(find.text('Drink more water today'), findsOneWidget);
      expect(find.text('Current'), findsOneWidget);
    });

    tallTest("shows the doctor's plan, with Read more for long plans", (t) async {
      final long = List.generate(8, (i) => 'Step ${i + 1}: keep going').join('\n');
      final repo = FakeDashboardRepository()
        ..plan = Stream.value(
          CarePlan(content: long, updatedAt: now.subtract(const Duration(hours: 3))),
        );
      await t.pumpWidget(app(repo));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('care-plan-text')), findsOneWidget);
      expect(find.textContaining('From your doctor · updated 3'), findsOneWidget);
      await t.tap(find.byKey(const Key('care-plan-more')));
      await t.pump();
      expect(find.text('Show less'), findsOneWidget);
    });
  });
}
