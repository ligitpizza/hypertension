import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hypertension/core/constants/enums.dart';
import 'package:hypertension/core/router/routers.dart' show patientAppGuard;
import 'package:hypertension/features/auth/state/auth_providers.dart';
import 'package:hypertension/features/dashboard/data/dashboard_repository.dart';
import 'package:hypertension/features/dashboard/state/dashboard_providers.dart';
import 'package:hypertension/features/family/data/family_repository.dart';
import 'package:hypertension/features/family/data/location_source.dart';
import 'package:hypertension/features/family/presentation/alert_page.dart';
import 'package:hypertension/features/family/presentation/family_dashboard_page.dart';
import 'package:hypertension/features/family/presentation/family_requests_page.dart';
import 'package:hypertension/features/family/presentation/link_page.dart';
import 'package:hypertension/features/family/presentation/sos_page.dart';
import 'package:hypertension/features/family/state/family_providers.dart';
import 'package:hypertension/features/symptom_checker/state/symptom_providers.dart';
import 'package:hypertension/shared/models/health_models.dart';
import 'package:hypertension/shared/services/api/api_client.dart';

import '../helpers/fakes.dart';

// FR-14.2 family monitoring (Figs 4.3.16.1-4.3.16.3, 4.3.9.1; UC15.1-UC15.3; D-62).

/// Fri 16 Oct 2026, 12:00 Malaysia time.
final now = DateTime.utc(2026, 10, 16, 4);

class FakeFamilyRepository implements FamilyRepository {
  String? linked;
  LinkRequest? pending;
  List<EmergencyAlert> alerts = [];
  List<LinkRequest> patientRequests = [];
  List<LinkedPerson> family = [];
  final calls = <String>[];
  ApiException? error;
  int sosAlerted = 1;

  @override
  Stream<String?> linkedPatientId(String familyUid) => Stream.value(linked);

  @override
  Stream<LinkRequest?> myPendingRequest(String familyUid) => Stream.value(pending);

  @override
  Stream<LinkedPerson?> person(String uid) => Stream.value(LinkedPerson(uid, 'Siti Aminah'));

  @override
  Stream<List<EmergencyAlert>> myAlerts(String familyUid) => Stream.value(alerts);

  @override
  Future<void> requestLink(String code) async {
    if (error != null) throw error!;
    calls.add('link:$code');
  }

  @override
  Future<void> withdraw(String requestId) async => calls.add('withdraw:$requestId');

  @override
  Future<void> unlink() async => calls.add('unlink');

  @override
  Future<void> acknowledge(String alertId) async => calls.add('ack:$alertId');

  @override
  Stream<List<LinkRequest>> pendingForPatient(String patientId) => Stream.value(patientRequests);

  @override
  Stream<List<LinkedPerson>> linkedFamily(String patientId) => Stream.value(family);

  @override
  Future<void> decide(String requestId, {required bool approve}) async =>
      calls.add('decide:$requestId:$approve');

  @override
  Future<void> removeMember(String uid) async => calls.add('remove:$uid');

  @override
  Future<int> sos({Map<String, double>? location, bool notifyFamily = true}) async {
    calls.add('sos:${location?['lat']}:$notifyFamily');
    return notifyFamily ? sosAlerted : 0;
  }

  @override
  Future<int> openEmergencies() async => 0;

  @override
  Future<void> updateLocation(Map<String, double> location) async => calls.add('loc');
}

class FakeLocation implements LocationSource {
  Map<String, double>? here = {'lat': 3.139, 'lng': 101.6869};
  final asked = <bool>[];

  @override
  Future<Map<String, double>?> current({bool ask = false}) async {
    asked.add(ask);
    return here;
  }

  @override
  Future<bool> granted() async => here != null;

  LocationAccess access = LocationAccess.granted;
  final settings = <LocationAccess>[];

  @override
  Future<LocationAccess> request() async {
    asked.add(true);
    return here == null ? access : LocationAccess.granted;
  }

  @override
  Future<void> openSettings(LocationAccess access) async => settings.add(access);
}

class FakeHealthData implements DashboardRepository {
  List<VitalReading> readings = [];
  RiskScore? risk;

  @override
  Stream<List<VitalReading>> recentReadings(String patientId, {int limit = 20}) =>
      Stream.value(readings);

  @override
  Stream<RiskScore?> latestRiskScore(String patientId) => Stream.value(risk);

  @override
  Stream<List<Medication>> medications(String patientId) => Stream.value(const []);

  @override
  Stream<CarePlan?> carePlan(String patientId) => Stream.value(null);

  @override
  Stream<List<CarePlanVersion>> carePlanHistory(String patientId) => Stream.value(const []);

  @override
  Stream<List<Appointment>> upcomingAppointments(String patientId, DateTime from) =>
      Stream.value(const []);
}

VitalReading reading(DateTime at, int sys, int dia, {int? hr}) => VitalReading(
  id: 'v${at.millisecondsSinceEpoch}',
  patientId: 'p1',
  systolic: sys,
  diastolic: dia,
  heartRate: hr,
  timestamp: at,
);

EmergencyAlert alert({
  String trigger = 'emergency_reading',
  bool located = true,
  bool acked = false,
  String? phone = '012-3456789',
  String? source,
}) => EmergencyAlert(
  id: 'e1',
  patientId: 'p1',
  familyMemberId: 'f1',
  trigger: trigger,
  sentAt: now.subtract(const Duration(minutes: 2)),
  lat: located ? 3.139 : null,
  lng: located ? 101.6869 : null,
  patientPhone: phone,
  acknowledgedAt: acked ? now : null,
  locationSource: source,
);

late FakeFamilyRepository repo;
late FakeLocation location;
late FakeHealthData health;
final dialled = <String>[];
final opened = <Uri>[];
final shared = <String>[];

Widget app(String initial, {String uid = 'f1'}) {
  final router = GoRouter(
    initialLocation: initial,
    routes: [
      GoRoute(path: '/family/home', builder: (_, _) => const FamilyDashboardPage()),
      GoRoute(path: '/family/link', builder: (_, _) => const LinkPage()),
      GoRoute(
        path: '/family/alert/:id',
        builder: (_, s) => AlertPage(alertId: s.pathParameters['id']!),
      ),
      GoRoute(path: '/family-requests', builder: (_, _) => const FamilyRequestsPage()),
      GoRoute(path: '/sos', builder: (_, _) => const SosPage()),
    ],
  );
  return ProviderScope(
    overrides: [
      familyRepositoryProvider.overrideWithValue(repo),
      locationSourceProvider.overrideWithValue(location),
      dashboardRepositoryProvider.overrideWithValue(health),
      nowProvider.overrideWithValue(() => now),
      authUidProvider.overrideWith((ref) => Stream.value(uid)),
      mapBuilderProvider.overrideWithValue((lat, lng, label) => Text('MAP $lat,$lng $label')),
      dialerProvider.overrideWithValue((n) async {
        dialled.add(n);
        return true;
      }),
      openUrlProvider.overrideWithValue((u) async {
        opened.add(u);
        return true;
      }),
      shareTextProvider.overrideWithValue((t) async => shared.add(t)),
      recentReadingsProvider.overrideWith((ref) => Stream.value(health.readings)),
    ],
    child: MaterialApp.router(routerConfig: router),
  );
}

void main() {
  setUp(() {
    repo = FakeFamilyRepository();
    location = FakeLocation();
    health = FakeHealthData();
    dialled.clear();
    opened.clear();
    shared.clear();
  });

  group('UC15.1 link (Fig 4.3.16.1)', () {
    tallTest('enter the code and send the request', (t) async {
      await t.pumpWidget(app('/family/link'));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('link-send')));
      await t.pump();
      expect(find.byKey(const Key('link-error')), findsOneWidget);
      await t.enterText(find.byKey(const Key('link-code')), 'ab12cd');
      await t.tap(find.byKey(const Key('link-send')));
      await t.pumpAndSettle();
      expect(repo.calls, ['link:ab12cd']);
    });

    tallTest('an invalid code shows the reason', (t) async {
      repo.error = ApiException('INVALID_CODE', 'No patient has this link code.');
      await t.pumpWidget(app('/family/link'));
      await t.pumpAndSettle();
      await t.enterText(find.byKey(const Key('link-code')), 'ZZZZZZ');
      await t.tap(find.byKey(const Key('link-send')));
      await t.pumpAndSettle();
      expect(find.text('No patient has this link code.'), findsOneWidget);
    });

    tallTest('E1 pending: waiting state with withdraw; dashboard explains', (t) async {
      repo.pending = const LinkRequest(
        id: 'r1',
        familyMemberId: 'f1',
        patientId: 'p1',
        status: 'pending',
      );
      await t.pumpWidget(app('/family/link'));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('link-pending')), findsOneWidget);
      await t.tap(find.byKey(const Key('link-withdraw')));
      await t.pumpAndSettle();
      expect(repo.calls, ['withdraw:r1']);
      await t.pumpWidget(app('/family/home'));
      await t.pumpAndSettle();
      expect(find.text('Waiting for approval'), findsOneWidget);
    });

    tallTest('linked: shows who you follow and unlinks after confirming', (t) async {
      repo.linked = 'p1';
      await t.pumpWidget(app('/family/link'));
      await t.pumpAndSettle();
      expect(find.text('Siti Aminah'), findsOneWidget);
      await t.tap(find.byKey(const Key('link-unlink')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('unlink-confirm')));
      await t.pumpAndSettle();
      expect(repo.calls, ['unlink']);
    });
  });

  group('Fig 4.3.16.2 family dashboard', () {
    tallTest('status, today\'s BP and HR, trend; no alert banner', (t) async {
      repo.linked = 'p1';
      health
        ..readings = [
          reading(now.subtract(const Duration(hours: 1)), 128, 82, hr: 72),
          reading(now.subtract(const Duration(days: 1)), 124, 80),
          reading(now.subtract(const Duration(days: 2)), 130, 85),
        ]
        ..risk = RiskScore(
          id: 's1',
          patientId: 'p1',
          scores: const {
            Complication.cad: ComplicationScore(value: 0.2, level: RiskLevel.moderate),
          },
          generatedAt: now,
          modelUsed: 'x',
        );
      await t.pumpWidget(app('/family/home'));
      await t.pumpAndSettle();
      expect(find.text('Siti Aminah'), findsOneWidget);
      expect(find.text('Moderate Risk'), findsOneWidget);
      expect(find.text('128/82 mmHg · +4 from yesterday'), findsOneWidget);
      expect(find.text('72 BPM (camera estimate)'), findsOneWidget);
      expect(find.byKey(const Key('family-alert-banner')), findsNothing);
    });

    tallTest('an open alert shows a banner that opens it', (t) async {
      repo
        ..linked = 'p1'
        ..alerts = [alert()];
      await t.pumpWidget(app('/family/home'));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('family-alert-banner')), findsOneWidget);
      await t.tap(find.byKey(const Key('family-alert-banner')));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('alert-badge')), findsOneWidget);
    });

    tallTest('acknowledged alerts no longer show a banner', (t) async {
      repo
        ..linked = 'p1'
        ..alerts = [alert(acked: true)];
      await t.pumpWidget(app('/family/home'));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('family-alert-banner')), findsNothing);
    });
  });

  group('Fig 4.3.16.3 emergency alert (UC15.2, UC15.3)', () {
    tallTest('D-70 a saved place is labelled as such', (t) async {
      repo
        ..linked = 'p1'
        ..alerts = [alert(source: 'saved')];
      await t.pumpWidget(app('/family/alert/e1'));
      await t.pumpAndSettle();
      expect(
        find.text('Saved home location (their phone shared no live location)'),
        findsOneWidget,
      );
    });

    tallTest('reading, map with update time, call, navigate, acknowledge', (t) async {
      repo
        ..linked = 'p1'
        ..alerts = [alert()];
      health.readings = [reading(now.subtract(const Duration(minutes: 3)), 185, 110)];
      await t.pumpWidget(app('/family/alert/e1'));
      await t.pumpAndSettle();
      expect(find.text('Critical BP reading'), findsOneWidget);
      expect(find.text('Detected 2 minutes ago'), findsOneWidget);
      expect(find.text('185/110 mmHg'), findsOneWidget);
      expect(find.text('MAP 3.139,101.6869 Siti Aminah'), findsOneWidget);
      expect(find.text('Phone location · updated 2 minutes ago'), findsOneWidget);
      await t.tap(find.byKey(const Key('alert-call-patient')));
      await t.tap(find.byKey(const Key('alert-call-999')));
      await t.tap(find.byKey(const Key('alert-navigate')));
      await t.tap(find.byKey(const Key('alert-ack')));
      await t.pumpAndSettle();
      expect(dialled, ['012-3456789', '999']);
      expect(opened.single.toString(), contains('destination=3.139,101.6869'));
      expect(repo.calls, ['ack:e1']);
    });

    tallTest('no location and no phone are explained, not hidden', (t) async {
      repo
        ..linked = 'p1'
        ..alerts = [alert(trigger: 'sos', located: false, phone: null)];
      await t.pumpWidget(app('/family/alert/e1'));
      await t.pumpAndSettle();
      expect(find.text('SOS pressed'), findsOneWidget);
      expect(find.byKey(const Key('alert-no-location')), findsOneWidget);
      expect(find.text('No phone number on file'), findsOneWidget);
      expect(t.widget<OutlinedButton>(find.byKey(const Key('alert-navigate'))).onPressed, isNull);
    });
  });

  group('patient side', () {
    tallTest('approve or reject requests; remove a linked member', (t) async {
      repo
        ..patientRequests = [
          const LinkRequest(
            id: 'r1',
            familyMemberId: 'f1',
            patientId: 'p1',
            status: 'pending',
            familyMemberName: 'Aisyah',
          ),
        ]
        ..family = [const LinkedPerson('f2', 'Ali')];
      await t.pumpWidget(app('/family-requests', uid: 'p1'));
      await t.pumpAndSettle();
      expect(find.text('Aisyah wants to follow your health'), findsOneWidget);
      await t.tap(find.byKey(const Key('family-approve-r1')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('family-remove-f2')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('family-remove-confirm')));
      await t.pumpAndSettle();
      expect(repo.calls, ['decide:r1:true', 'remove:f2']);
      expect(
        find.textContaining('Your live location is sent only with an emergency alert'),
        findsWidgets, // D-70: in the map card and its status line
      );
    });

    tallTest('SOS (Fig 4.3.9.1): map, alert family then call 999', (t) async {
      health.readings = [reading(now.subtract(const Duration(hours: 1)), 150, 95, hr: 88)];
      await t.pumpWidget(app('/sos', uid: 'p1'));
      await t.pumpAndSettle();
      expect(location.asked.first, isTrue); // SOS asks for location on purpose
      expect(find.text('MAP 3.139,101.6869 You are here'), findsOneWidget);
      await t.tap(find.byKey(const Key('sos-call-999')));
      await t.pumpAndSettle();
      expect(repo.calls, ['sos:3.139:true']);
      expect(dialled, ['999']);
      expect(find.text('Family alerted (1) and your doctor notified.'), findsOneWidget);
      await t.tap(find.byKey(const Key('sos-share')));
      await t.tap(find.byKey(const Key('sos-hospitals')));
      await t.pumpAndSettle();
      expect(shared.single, contains('150/95 mmHg, HR 88 (camera estimate)'));
      expect(opened.single.toString(), contains('maps/search/hospital'));
    });

    tallTest('SOS without notifying family only tells the doctor', (t) async {
      await t.pumpWidget(app('/sos', uid: 'p1'));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('sos-notify')));
      await t.pump();
      await t.tap(find.byKey(const Key('sos-alert-only')));
      await t.pumpAndSettle();
      expect(repo.calls, ['sos:3.139:false']);
      expect(dialled, isEmpty);
      expect(find.text('Your doctor has been notified.'), findsOneWidget);
    });
  });

  test('alert titles and the "ago" label', () {
    expect(alert(trigger: 'critical_risk').title, 'Critical health risk');
    expect(agoLabel(now.subtract(const Duration(minutes: 1)), now), '1 minute ago');
    expect(agoLabel(now.subtract(const Duration(hours: 3)), now), '3 hours ago');
  });

  group('location problems are explained (D-62 follow-up)', () {
    tallTest('GPS off: Family page offers to turn it on', (t) async {
      location
        ..here = null
        ..access = LocationAccess.serviceOff;
      await t.pumpWidget(app('/family-requests', uid: 'p1'));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('family-location-allow')));
      await t.pumpAndSettle();
      expect(find.textContaining('location (GPS) is turned off'), findsOneWidget);
      expect(find.text('Turn on location'), findsOneWidget);
      await t.tap(find.byKey(const Key('family-location-allow')));
      await t.pumpAndSettle();
      expect(location.settings, [LocationAccess.serviceOff]);
    });

    tallTest('permission refused for good: SOS points to app settings', (t) async {
      location
        ..here = null
        ..access = LocationAccess.deniedForever;
      await t.pumpWidget(app('/sos', uid: 'p1'));
      await t.pumpAndSettle();
      expect(find.textContaining('Allow it for CareFlow'), findsOneWidget);
      await t.tap(find.byKey(const Key('sos-location-retry')));
      await t.pumpAndSettle();
      expect(location.settings, [LocationAccess.deniedForever]);
    });

    tallTest('an SOS alert explains the patient asked for help', (t) async {
      repo
        ..linked = 'p1'
        ..alerts = [alert(trigger: 'sos')];
      await t.pumpWidget(app('/family/alert/e1'));
      await t.pumpAndSettle();
      expect(find.textContaining('Siti Aminah asked for help'), findsOneWidget);
    });
  });

  group('D-63 one app for patients and family', () {
    test('each role lands on its own home and stays out of the other side', () {
      expect(patientAppGuard('/start', UserRole.familyMember), '/family/home');
      expect(patientAppGuard('/start', UserRole.patient), '/dashboard');
      expect(patientAppGuard('/dashboard', UserRole.familyMember), '/family/home');
      expect(patientAppGuard('/family-requests', UserRole.familyMember), '/family/home');
      expect(patientAppGuard('/family/home', UserRole.patient), '/dashboard');
      expect(patientAppGuard('/family-requests', UserRole.patient), isNull);
      expect(patientAppGuard('/family/alert/e1', UserRole.familyMember), isNull);
      expect(patientAppGuard('/login', null), isNull);
    });
  });
}
