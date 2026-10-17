import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hypertension/features/dashboard/state/dashboard_providers.dart';
import 'package:hypertension/features/provider_portal/presentation/prescriptions_overview_page.dart';
import 'package:hypertension/features/staff_shell/admin_center.dart';
import 'package:hypertension/features/vitals/presentation/vitals_page.dart';
import 'package:hypertension/shared/models/health_models.dart';
import 'package:hypertension/shared/providers/api_providers.dart';

import '../helpers/fakes.dart';

// D-78: admin center, doctor prescription management, Vitals tab and dev BP tools.

class D78Api extends FakeApiClient {
  final calls = <String>[];
  List<Map<String, dynamic>> requests = [];
  List<Map<String, dynamic>> prescriptions = [];
  bool devTools = false;

  @override
  Future<Map<String, dynamic>> staffRequests() async => {'requests': requests};

  @override
  Future<Map<String, dynamic>> createStaffRequest(
    String category,
    String subject,
    String details,
  ) async {
    calls.add('create:$category:$subject');
    return {};
  }

  @override
  Future<Map<String, dynamic>> updateStaffRequest(
    String id, {
    String? status,
    String? reply,
  }) async {
    calls.add('update:$id:$status:$reply');
    return {};
  }

  @override
  Future<Map<String, dynamic>> doctorPrescriptions() async => {'prescriptions': prescriptions};

  @override
  Future<Map<String, dynamic>> setRecurring(String prescriptionId, bool recurring) async {
    calls.add('recurring:$prescriptionId:$recurring');
    return {};
  }

  @override
  Future<Map<String, dynamic>> vitalsDevTools() async => {'enabled': devTools};

  @override
  Future<Map<String, dynamic>> deleteReading(String id) async {
    calls.add('delete:$id');
    return {'rescored': true};
  }

  @override
  Future<Map<String, dynamic>> clearReadings() async {
    calls.add('clear');
    return {'deleted': 2};
  }
}

late D78Api api;
final now = DateTime(2026, 10, 17, 20);

Widget host(Widget page, {List<VitalReading> readings = const []}) {
  final router = GoRouter(
    routes: [
      GoRoute(
        path: '/',
        builder: (_, _) => Scaffold(body: page),
      ),
      GoRoute(
        path: '/doctor/patient/:id',
        builder: (_, s) => Text('PATIENT ${s.pathParameters['id']}'),
      ),
      GoRoute(
        path: '/doctor/patient/:id/prescriptions',
        builder: (_, s) => Text('EDIT ${s.pathParameters['id']}'),
      ),
    ],
  );
  return ProviderScope(
    overrides: [
      apiClientProvider.overrideWithValue(api),
      recentReadingsProvider.overrideWith((ref) => Stream.value(readings)),
      latestRiskProvider.overrideWith((ref) => Stream.value(null)),
      nowProvider.overrideWithValue(() => now),
    ],
    child: MaterialApp.router(routerConfig: router),
  );
}

Future<void> wide(WidgetTester t) async {
  t.view.physicalSize = const Size(1300, 1400);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
}

Future<void> tall(WidgetTester t) async {
  t.view.physicalSize = const Size(500, 2400);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
}

VitalReading reading(String id, int s, int d, DateTime at) =>
    VitalReading(id: id, patientId: 'p1', systolic: s, diastolic: d, timestamp: at);

void main() {
  setUp(() => api = D78Api());

  testWidgets('admin center: a pharmacist sends a request and sees the reply', (t) async {
    await wide(t);
    api.requests = [
      {
        'id': 's1',
        'category': 'stock',
        'subject': 'Supplier late',
        'details': 'Amlodipine two weeks late.',
        'status': 'in_progress',
        'reply': 'Ordered elsewhere.',
        'repliedBy': 'Admin Lee',
      },
    ];
    await t.pumpWidget(host(const AdminCenterPage()));
    await t.pumpAndSettle();
    expect(find.text('Supplier late'), findsOneWidget);
    expect(find.byKey(const Key('reply-s1')), findsOneWidget);
    expect(find.text('In progress'), findsWidgets);

    await t.tap(find.byKey(const Key('new-request')));
    await t.pumpAndSettle();
    await t.enterText(find.byKey(const Key('request-subject')), 'Printer broken');
    await t.enterText(find.byKey(const Key('request-details')), 'Label printer jammed.');
    await t.tap(find.byKey(const Key('request-send')));
    await t.pumpAndSettle();
    expect(api.calls, contains('create:other:Printer broken'));
  });

  testWidgets('admin replies to a staff request', (t) async {
    await wide(t);
    api.requests = [
      {
        'id': 's1',
        'category': 'leave',
        'subject': 'Leave on Friday',
        'details': 'Family event.',
        'status': 'open',
        'requesterName': 'Dr Tan',
        'requesterRole': 'doctor',
      },
    ];
    await t.pumpWidget(host(const AdminRequestsPage()));
    await t.pumpAndSettle();
    expect(find.textContaining('Dr Tan (doctor)'), findsOneWidget);
    await t.tap(find.byKey(const Key('reply-button-s1')));
    await t.pumpAndSettle();
    await t.enterText(find.byKey(const Key('reply-text')), 'Approved.');
    await t.tap(find.byKey(const Key('reply-save')));
    await t.pumpAndSettle();
    expect(api.calls, contains('update:s1:in_progress:Approved.'));
  });

  testWidgets('doctor prescriptions: list, counts, filter and stop the monthly repeat', (t) async {
    await wide(t);
    api.prescriptions = [
      {
        'id': 'rx1',
        'patientId': 'p1',
        'patientName': 'Siti',
        'medicationDetails': 'Amlodipine 5mg x30',
        'items': [{}],
        'total': 9.0,
        'isRecurring': true,
        'issuedAt': '2026-10-15T02:00:00Z',
        'latestOrder': {'ref': 'CF-ABC123', 'status': 'awaiting_payment'},
      },
      {
        'id': 'rx2',
        'patientId': 'p2',
        'patientName': 'Ali',
        'medicationDetails': 'Losartan 50mg',
        'isRecurring': false,
        'latestOrder': null,
      },
    ];
    await t.pumpWidget(host(const PrescriptionsOverviewPage()));
    await t.pumpAndSettle();
    expect(find.text('Waiting for payment'), findsOneWidget);
    expect(find.text('No order yet'), findsOneWidget);
    expect(find.textContaining('RM9.00/month'), findsOneWidget);

    await t.tap(find.text('One-off'));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('rx-rx1')), findsNothing);
    expect(find.byKey(const Key('rx-rx2')), findsOneWidget);

    await t.tap(find.text('All'));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('rx-stop-rx1')));
    await t.pumpAndSettle();
    await t.tap(find.text('Stop'));
    await t.pumpAndSettle();
    expect(api.calls, contains('recurring:rx1:false'));

    await t.tap(find.byKey(const Key('rx-edit-rx2')));
    await t.pumpAndSettle();
    expect(find.text('EDIT p2'), findsOneWidget);
  });

  testWidgets('vitals: crisis colour and warning, day groups, no dev tools by default', (t) async {
    await tall(t);
    await t.pumpWidget(
      host(
        const VitalsPage(),
        readings: [
          reading('a', 200, 150, now.subtract(const Duration(hours: 1))),
          reading('b', 130, 80, now.subtract(const Duration(days: 1))),
        ],
      ),
    );
    await t.pumpAndSettle();
    expect(find.byKey(const Key('vitals-crisis')), findsOneWidget);
    expect(find.text('+70 from yesterday'), findsOneWidget);
    expect(find.text('Today'), findsOneWidget);
    expect(find.text('Yesterday'), findsOneWidget);
    expect(find.byKey(const Key('vitals-dev-bar')), findsNothing);
    expect(find.byKey(const Key('delete-reading-a')), findsNothing);
  });

  testWidgets('vitals dev tools: delete one reading and clear all', (t) async {
    api.devTools = true;
    await tall(t);
    await t.pumpWidget(
      host(
        const VitalsPage(),
        readings: [
          reading('a', 128, 82, now.subtract(const Duration(hours: 1))),
          reading('b', 130, 80, now.subtract(const Duration(days: 1))),
        ],
      ),
    );
    await t.pumpAndSettle();
    await t.ensureVisible(find.byKey(const Key('delete-reading-a')));
    await t.tap(find.byKey(const Key('delete-reading-a')));
    await t.pumpAndSettle();
    await t.tap(find.text('Delete'));
    await t.pumpAndSettle();
    expect(api.calls, contains('delete:a'));

    await t.ensureVisible(find.byKey(const Key('vitals-clear-all')));
    await t.tap(find.byKey(const Key('vitals-clear-all')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('vitals-clear-confirm')));
    await t.pumpAndSettle();
    expect(api.calls, contains('clear'));
  });
}
