import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hypertension/core/constants/enums.dart';
import 'package:hypertension/features/admin/state/admin_providers.dart';
import 'package:hypertension/features/appointments/state/appointment_providers.dart';
import 'package:hypertension/features/auth/domain/app_user.dart';
import 'package:hypertension/features/provider_portal/state/portal_providers.dart';
import 'package:hypertension/features/auth/state/auth_providers.dart';
import 'package:hypertension/features/notifications/data/notifications_repository.dart';
import 'package:hypertension/features/notifications/state/notification_providers.dart';
import 'package:hypertension/features/orders/data/order_models.dart';
import 'package:hypertension/features/orders/state/orders_providers.dart';
import 'package:hypertension/features/staff_shell/dashboards.dart';
import 'package:hypertension/features/staff_shell/staff_settings_page.dart';
import 'package:hypertension/features/staff_shell/staff_shell.dart';
import 'package:hypertension/shared/providers/api_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/fakes.dart';
import '../helpers/order_fakes.dart';

// D-77: portal bell, Settings, grey nav rail and dashboards.

class FakeNotifications implements NotificationsRepository {
  List<AppNotification> items = [];
  Map<String, bool> saved = {for (final c in bellCategories.keys) c: true};
  final calls = <String>[];

  @override
  Future<NotificationInbox> inbox() async =>
      NotificationInbox(items, items.where((n) => !n.read).length);

  @override
  Future<void> markRead(String id) async => calls.add('read:$id');

  @override
  Future<void> markAllRead() async => calls.add('all');

  @override
  Future<Map<String, bool>> prefs() async => saved;

  @override
  Future<void> savePrefs(Map<String, bool> prefs) async {
    calls.add('prefs');
    saved = prefs;
  }
}

class FakeStaffApi extends FakeApiClient {
  Map<String, dynamic> profile = {
    'name': 'Dr Tan',
    'email': 'tan@harvey.my',
    'role': 'doctor',
    'specialty': 'Cardiology',
  };
  Map<String, dynamic>? saved;

  @override
  Future<Map<String, dynamic>> staffProfile() async => profile;

  @override
  Future<Map<String, dynamic>> updateStaffProfile({
    required String name,
    String? phone,
    String? specialty,
  }) async {
    saved = {'name': name, 'phone': phone, 'specialty': specialty};
    return {'status': 'ok'};
  }
}

late FakeNotifications notes;
late FakeStaffApi api;
late FakeAuthRepository auth;
late FakeOrdersRepository orders;

AppUser staff(UserRole role) => AppUser(
  uid: 'u1',
  email: 'tan@harvey.my',
  name: 'Dr Tan',
  role: role,
  isActive: true,
  onboardingComplete: true,
);

Widget portal(String location, UserRole role, Widget page) {
  final router = GoRouter(
    initialLocation: location,
    routes: [
      ShellRoute(
        builder: (_, s, child) => StaffShell(location: s.matchedLocation, child: child),
        routes: [
          GoRoute(path: location, builder: (_, _) => page),
          for (final p in ['/doctor/settings', '/doctor/messages/p1', '/pharmacy'])
            if (p != location) GoRoute(path: p, builder: (_, _) => Text('ROUTE $p')),
        ],
      ),
    ],
  );
  return ProviderScope(
    overrides: [
      notificationsRepositoryProvider.overrideWithValue(notes),
      apiClientProvider.overrideWithValue(api),
      authRepositoryProvider.overrideWithValue(auth),
      ordersRepositoryProvider.overrideWithValue(orders),
      currentUserProvider.overrideWith((ref) => Stream.value(staff(role))),
      authUidProvider.overrideWith((ref) => Stream.value('u1')),
    ],
    child: MaterialApp.router(routerConfig: router),
  );
}

Future<void> wide(WidgetTester t) async {
  t.view.physicalSize = const Size(1400, 1000);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
}

AppNotification note(String id, String title, {String? type, Map<String, String>? data}) =>
    AppNotification(
      id: id,
      title: title,
      body: 'Body of $title',
      category: 'messages',
      read: false,
      type: type,
      data: data ?? const {},
      createdAt: DateTime.utc(2026, 10, 17, 1),
    );

void main() {
  setUp(() {
    notes = FakeNotifications();
    api = FakeStaffApi();
    auth = FakeAuthRepository();
    orders = FakeOrdersRepository();
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('top bar has the bell; nav rail is grey with Settings at the bottom', (t) async {
    await wide(t);
    notes.items = [
      note('n1', 'Message from Siti', type: 'message', data: {'from': 'p1'}),
    ];
    await t.pumpWidget(portal('/doctor/dashboard', UserRole.doctor, const Text('DASH')));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('notification-bell')), findsOneWidget);
    expect(
      find.descendant(of: find.byKey(const Key('bell-badge')), matching: find.text('1')),
      findsOneWidget,
    );
    expect(t.widget<NavigationRail>(find.byType(NavigationRail)).backgroundColor, isNotNull);
    await t.tap(find.byKey(const Key('staff-settings')));
    await t.pumpAndSettle();
    expect(find.text('ROUTE /doctor/settings'), findsOneWidget);
  });

  testWidgets('the bell panel opens a notification and marks it read', (t) async {
    await wide(t);
    notes.items = [
      note('n1', 'Message from Siti', type: 'message', data: {'from': 'p1'}),
    ];
    await t.pumpWidget(portal('/doctor/dashboard', UserRole.doctor, const Text('DASH')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('notification-bell')));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('unread-dot-n1')), findsOneWidget);
    await t.tap(find.byKey(const Key('notification-n1')));
    await t.pumpAndSettle();
    expect(notes.calls, contains('read:n1'));
    expect(find.text('ROUTE /doctor/messages/p1'), findsOneWidget);
  });

  testWidgets('pharmacist dashboard counts what needs attention', (t) async {
    await wide(t);
    orders
      ..queueData = PharmacyQueue(
        orders: [
          anOrder(id: 'a', status: Fulfilment.preparing, paymentStatus: 'paid'),
          anOrder(id: 'b', status: Fulfilment.readyForCollection, paymentStatus: 'paid'),
          anOrder(
            id: 'c',
            status: Fulfilment.readyForDelivery,
            paymentStatus: 'paid',
            method: homeDelivery,
            deliveryStatus: 'in_transit',
          ),
        ],
        needsPrice: const [],
      )
      ..stockItems = const [
        StockItem(id: 's1', name: 'Amlodipine 5mg', units: 0, lowStockAt: 20, low: true),
        StockItem(id: 's2', name: 'Losartan 50mg', units: 300, lowStockAt: 20, low: false),
      ];
    await t.pumpWidget(
      portal('/pharmacy/dashboard', UserRole.pharmacist, const PharmacyDashboardPage()),
    );
    await t.pumpAndSettle();
    expect(find.byKey(const Key('pharmacy-dashboard')), findsOneWidget);
    StatTile tile(String label) =>
        t.widget<StatTile>(find.ancestor(of: find.text(label), matching: find.byType(StatTile)));
    expect(tile('To prepare').value, '1');
    expect(tile('Ready for collection or courier').value, '1');
    expect(tile('Out for delivery').value, '1');
    expect(tile('Low or out of stock').value, '1');
    expect(find.text('Amlodipine 5mg'), findsOneWidget);
  });

  testWidgets('settings: profile, password reset and bell categories', (t) async {
    await wide(t);
    await t.pumpWidget(portal('/doctor/settings', UserRole.doctor, const StaffSettingsPage()));
    await t.pumpAndSettle();
    await t.enterText(find.byKey(const Key('staff-phone')), '012-345 6789');
    await t.tap(find.byKey(const Key('staff-profile-save')));
    await t.pumpAndSettle();
    expect(api.saved, {'name': 'Dr Tan', 'phone': '012-345 6789', 'specialty': 'Cardiology'});

    await t.ensureVisible(find.byKey(const Key('staff-password-reset')));
    await t.tap(find.byKey(const Key('staff-password-reset')));
    await t.pumpAndSettle();
    expect(auth.calls, contains('reset'));
    expect(find.textContaining('We sent a link to tan@harvey.my'), findsOneWidget);

    await t.ensureVisible(find.byKey(const Key('bell-pref-orders')));
    await t.tap(find.byKey(const Key('bell-pref-orders')));
    await t.pumpAndSettle();
    expect(notes.saved['orders'], isFalse);
  });

  test('notifications lead to the right page for each role', () {
    expect(notificationRoute('message', {'from': 'd1'}, UserRole.patient), '/chat/d1');
    expect(notificationRoute('weekly_summary', const {}, UserRole.patient), '/ai-agent');
    expect(notificationRoute('conversation', {'id': 'c1'}, UserRole.admin), '/admin/messages/c1');
    expect(
      notificationRoute('conversation', {'id': 'c1'}, UserRole.pharmacist),
      '/pharmacy/messages/team/c1',
    );
    expect(notificationRoute('order', const {}, UserRole.pharmacist), '/pharmacy');
    expect(notificationRoute('clinical_alert', const {}, UserRole.doctor), '/doctor');
    expect(notificationRoute('unknown', const {}, UserRole.doctor), isNull);
  });

  testWidgets('doctor and admin dashboards render even when sources fail', (t) async {
    await wide(t);
    final failing = [
      assignedPatientsProvider.overrideWith((ref) => Stream.value(const [])),
      openAlertsProvider.overrideWith((ref) => Stream.value(const [])),
      doctorAppointmentsProvider.overrideWith((ref, k) => Stream.value(const [])),
      pendingAssignmentRequestsProvider.overrideWith((ref) => Stream.value(const [])),
      allAppointmentsProvider.overrideWith((ref, k) => Stream.value(const [])),
      auditLogsProvider.overrideWith((ref, q) => throw StateError('offline')),
      hospitalAnalyticsProvider.overrideWith((ref) => throw StateError('offline')),
      systemAnalyticsProvider.overrideWith((ref, d) => throw StateError('offline')),
    ];
    for (final (role, page, key) in [
      (UserRole.doctor, const DoctorHomeDashboard(), 'doctor-dashboard'),
      (UserRole.admin, const AdminDashboardPage(), 'admin-dashboard'),
    ]) {
      await t.pumpWidget(
        ProviderScope(
          overrides: [
            ...failing,
            notificationsRepositoryProvider.overrideWithValue(notes),
            ordersRepositoryProvider.overrideWithValue(orders),
            currentUserProvider.overrideWith((ref) => Stream.value(staff(role))),
            authUidProvider.overrideWith((ref) => Stream.value('u1')),
          ],
          child: MaterialApp(home: Scaffold(body: page)),
        ),
      );
      await t.pumpAndSettle();
      expect(find.byKey(Key(key)), findsOneWidget);
      expect(t.takeException(), isNull);
    }
    expect(find.text('Could not load.'), findsWidgets);
  });
}
