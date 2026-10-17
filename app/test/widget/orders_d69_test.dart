import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hypertension/features/family/data/location_source.dart';
import 'package:hypertension/features/family/state/family_providers.dart';
import 'package:hypertension/features/orders/data/order_models.dart';
import 'package:hypertension/features/orders/presentation/address_page.dart';
import 'package:hypertension/features/orders/presentation/order_confirm_page.dart';
import 'package:hypertension/features/orders/presentation/order_track_page.dart';
import 'package:hypertension/features/orders/presentation/orders_page.dart';
import 'package:hypertension/features/orders/presentation/pharmacy_chat_pages.dart';
import 'package:hypertension/features/orders/presentation/pharmacy_page.dart';
import 'package:hypertension/features/orders/presentation/pharmacy_patient_page.dart';
import 'package:hypertension/features/orders/state/orders_providers.dart';

import 'package:hypertension/features/auth/state/auth_providers.dart';
import 'package:hypertension/features/messaging/state/messaging_providers.dart';
import '../helpers/conversation_fakes.dart';
import '../helpers/fakes.dart';
import '../helpers/order_fakes.dart';
import 'package:hypertension/features/orders/presentation/inventory_page.dart';
import 'package:hypertension/features/orders/presentation/pharmacy_patients_page.dart';
import 'package:hypertension/features/orders/presentation/staff_order_page.dart';
import 'package:hypertension/features/orders/presentation/tracking_page.dart';

// D-69: consolidated orders, Orders tabs, address picker, pharmacy patient view, catalogue
// and pharmacy chat.

late FakeOrdersRepository repo;
late FakeOrderLocation location;
final geocoded = <(double, double)>[];

const id = 'rx1_2026-10';

final items = [
  const OrderItem(
    catalogId: 'amlodipine-5',
    name: 'Amlodipine',
    strength: '5mg',
    dose: '1 tablet',
    frequency: 'once_daily',
    quantity: 30,
    unitPrice: 0.30,
  ),
  const OrderItem(
    catalogId: 'losartan-50',
    name: 'Losartan',
    strength: '50mg',
    dose: '1 tablet',
    frequency: 'twice_daily',
    quantity: 60,
    unitPrice: 0.90,
  ),
];

MedicationOrder itemOrder({
  String oid = id,
  Fulfilment status = Fulfilment.awaitingConfirmation,
  String paymentStatus = 'pending',
  String? suggestedAddress,
  double? lat,
  double? lng,
}) => MedicationOrder(
  id: oid,
  ref: 'CF-ABC123',
  patientId: 'u-patient',
  patientName: 'Siti',
  prescriptionId: 'rx1',
  medicationDetails: 'Amlodipine 5mg 1 tablet, once daily x30; Losartan 50mg ...',
  status: status,
  paymentStatus: paymentStatus,
  amount: 63,
  total: 63,
  items: items,
  cycleDate: DateTime.utc(2026, 10, 16, 2),
  suggestedAddress: suggestedAddress,
  suggestedLat: lat,
  suggestedLng: lng,
);

Widget host(String initial) {
  final router = GoRouter(
    initialLocation: initial,
    routes: [
      GoRoute(path: '/orders', builder: (_, _) => const OrdersPage()),
      GoRoute(
        path: '/orders/:id/confirm',
        builder: (_, s) => OrderConfirmPage(orderId: s.pathParameters['id']!),
      ),
      GoRoute(path: '/orders/:id/pay', builder: (_, _) => const Text('PAY')),
      GoRoute(path: '/orders/:id/track', builder: (_, _) => const Text('TRACK')),
      GoRoute(path: '/settings/address', builder: (_, _) => const AddressPage()),
      GoRoute(path: '/pharmacy-chat', builder: (_, _) => const PatientPharmacyChatPage()),
      GoRoute(
        path: '/pharmacy',
        builder: (_, _) => const Scaffold(body: PharmacyPage()),
        routes: [
          GoRoute(
            path: 'inventory',
            builder: (_, _) => const Scaffold(body: InventoryPage()),
          ),
          GoRoute(
            path: 'tracking',
            builder: (_, _) => const Scaffold(body: OrderTrackingPage()),
          ),
          GoRoute(
            path: 'admin-inventory',
            builder: (_, _) => const Scaffold(body: InventoryPage(admin: true)),
          ),
          GoRoute(
            path: 'patients',
            builder: (_, _) => const Scaffold(body: PharmacyPatientsPage()),
          ),
          GoRoute(
            path: 'patients/:uid',
            builder: (_, s) =>
                Scaffold(body: PharmacyPatientPage(patientId: s.pathParameters['uid']!)),
          ),
          GoRoute(
            path: 'messages',
            builder: (_, _) => const Scaffold(body: PharmacyMessagesPage()),
            routes: [
              GoRoute(
                path: ':uid',
                builder: (_, s) =>
                    Scaffold(body: PharmacyThreadPage(patientId: s.pathParameters['uid']!)),
              ),
            ],
          ),
        ],
      ),
    ],
  );
  return ProviderScope(
    overrides: [
      ordersRepositoryProvider.overrideWithValue(repo),
      // D-76: the pharmacist's team chats and per-device unread state.
      conversationsRepositoryProvider.overrideWithValue(FakeConversationsRepository()),
      authUidProvider.overrideWith((ref) => Stream.value('u-pharm')),
      locationSourceProvider.overrideWithValue(location),
      mapBuilderProvider.overrideWithValue((lat, lng, label) => Text('PREVIEW $lat,$lng')),
      pickerMapBuilderProvider.overrideWithValue(
        (lat, lng, onMoved) => GestureDetector(
          key: const Key('fake-map'),
          onTap: () => onMoved(5.4588, 100.2886),
          child: Text('MAP $lat,$lng'),
        ),
      ),
      reverseGeocoderProvider.overrideWithValue((lat, lng) async {
        geocoded.add((lat, lng));
        return 'Lorong Lembah Permai 3, 11200 Tanjung Bungah, Pulau Pinang';
      }),
    ],
    child: MaterialApp.router(routerConfig: router),
  );
}

void main() {
  setUp(() {
    repo = FakeOrdersRepository();
    location = FakeOrderLocation();
    geocoded.clear();
  });

  tallTest('Orders tabs split active and completed', (t) async {
    repo.orders = {
      id: itemOrder(),
      'rx2_2026-09': itemOrder(
        oid: 'rx2_2026-09',
        status: Fulfilment.delivered,
        paymentStatus: 'paid',
      ),
    };
    await t.pumpWidget(host('/orders'));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('order-$id')), findsOneWidget);
    expect(find.byKey(const Key('order-rx2_2026-09')), findsNothing);
    expect(find.textContaining('Amlodipine 5mg ×30, Losartan 50mg ×60'), findsOneWidget);
    await t.tap(find.byKey(const Key('orders-tab-completed')));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('order-rx2_2026-09')), findsOneWidget);
    expect(find.textContaining('Paid'), findsOneWidget);
  });

  tallTest('consolidated order shows each medicine and prefills the saved address', (t) async {
    repo.orders = {
      id: itemOrder(suggestedAddress: '77 Lorong Lembah Permai 3', lat: 5.4588, lng: 100.2886),
    };
    await t.pumpWidget(host('/orders/$id/confirm'));
    await t.pumpAndSettle();
    expect(find.text('Amlodipine 5mg'), findsOneWidget);
    expect(find.text('1 tablet, once daily · 30 × RM0.30'), findsOneWidget);
    expect(find.text('RM54.00'), findsOneWidget);
    await t.tap(find.byKey(const Key('method-delivery')));
    await t.pumpAndSettle();
    expect(find.text('77 Lorong Lembah Permai 3'), findsOneWidget);
    expect(find.text('Location shared for the courier'), findsOneWidget);
    // D-71: the saved drop-off is quoted straight away (RM63 + RM13.80 courier).
    expect(repo.calls, contains('quote:$id:5.4588,100.2886'));
    expect(t.widget<Text>(find.byKey(const Key('delivery-fee'))).data, 'RM13.80');
    expect(find.text('Delivery (Lalamove quote)'), findsOneWidget);
    expect(t.widget<Text>(find.byKey(const Key('order-total'))).data, 'RM76.80');
  });

  tallTest('pick the drop-off on the map at checkout', (t) async {
    repo.orders = {id: itemOrder()};
    await t.pumpWidget(host('/orders/$id/confirm'));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('method-delivery')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('pick-on-map')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('fake-map')));
    await t.pumpAndSettle();
    expect(geocoded, [(5.4588, 100.2886)]);
    await t.tap(find.byKey(const Key('address-save')));
    await t.pumpAndSettle();
    expect(find.textContaining('Tanjung Bungah'), findsOneWidget);
    expect(find.text('Location shared for the courier'), findsOneWidget);
    expect(repo.calls.where((c) => c.startsWith('address:')), isEmpty); // not saved to profile
  });

  tallTest('Settings address: current location fills the text and saves', (t) async {
    await t.pumpWidget(host('/settings/address'));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('address-current')));
    await t.pumpAndSettle();
    expect(geocoded.single, (3.1579, 101.7123));
    await t.tap(find.byKey(const Key('address-save')));
    await t.pumpAndSettle();
    expect(
      repo.calls,
      contains(
        'address:Lorong Lembah Permai 3, 11200 Tanjung Bungah, Pulau Pinang:3.1579,101.7123',
      ),
    );
  });

  tallTest('address without a pin is refused; refused location opens settings', (t) async {
    location
      ..here = null
      ..access = LocationAccess.deniedForever;
    await t.pumpWidget(host('/settings/address'));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('address-save')));
    await t.pumpAndSettle();
    expect(find.textContaining('Set the pin on the map'), findsOneWidget);
    await t.tap(find.byKey(const Key('address-current')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('address-current')));
    await t.pumpAndSettle();
    expect(location.settings, [LocationAccess.deniedForever]);
  });

  tallTest('pharmacy marks a consolidated order ready without choosing stock', (t) async {
    repo.queueData = PharmacyQueue(
      orders: [itemOrder(status: Fulfilment.preparing, paymentStatus: 'paid')],
      needsPrice: const [],
    );
    await t.pumpWidget(host('/pharmacy'));
    await t.pumpAndSettle();
    expect(find.textContaining('Amlodipine 5mg ×30, Losartan 50mg ×60'), findsOneWidget);
    await t.tap(find.byKey(const Key('ready-$id')));
    await t.pumpAndSettle();
    expect(find.text('• Losartan 50mg × 60'), findsOneWidget);
    await t.tap(find.byKey(const Key('ready-confirm')));
    await t.pumpAndSettle();
    expect(repo.calls, contains('ready:$id'));
  });

  tallTest('D-70 catalogue tab: edit a medicine and stop offering it', (t) async {
    await t.pumpWidget(host('/pharmacy/inventory'));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('inventory-tab-catalogue')));
    await t.pumpAndSettle();
    expect(find.text('RM0.30'), findsOneWidget);
    await t.ensureVisible(find.byKey(const Key('catalog-edit-amlodipine-5')));
    await t.tap(find.byKey(const Key('catalog-edit-amlodipine-5')));
    await t.pumpAndSettle();
    await t.enterText(find.byKey(const Key('catalog-edit-price')), '0.35');
    await t.pump();
    await t.tap(find.byKey(const Key('catalog-edit-save')));
    await t.pumpAndSettle();
    expect(repo.calls, contains('editCatalog:amlodipine-5:Amlodipine:5mg:0.35:'));
    await t.ensureVisible(find.byKey(const Key('catalog-active-losartan-50')));
    await t.tap(find.byKey(const Key('catalog-active-losartan-50')));
    await t.pumpAndSettle();
    expect(repo.calls, contains('editCatalog:losartan-50::::false'));
  });

  tallTest('pharmacist patient view: allergies, medicines, prescriptions, orders', (t) async {
    repo.patientDetail = PharmacyPatientDetail(
      id: 'u-patient',
      name: 'Siti Aminah',
      age: 58,
      gender: 'female',
      phone: '012-345 6789',
      allergies: 'Penicillin',
      conditions: const ['diabetes'],
      medications: const [
        PatientMedicine(
          name: 'Amlodipine 5mg',
          dosage: '1 tablet',
          schedule: '08:00',
          quantityOnHand: 30,
          fromDoctor: true,
          prescribedBy: 'Dr Tan',
        ),
      ],
      prescriptions: [PatientPrescription(id: 'rx1', medicationDetails: 'x', items: items)],
      orders: [itemOrder(status: Fulfilment.preparing, paymentStatus: 'paid')],
    );
    await t.pumpWidget(host('/pharmacy/patients/u-patient'));
    await t.pumpAndSettle();
    expect(find.text('Allergies: Penicillin'), findsOneWidget);
    expect(find.textContaining('58 years'), findsOneWidget);
    expect(find.textContaining('from Dr Tan'), findsOneWidget);
    expect(find.textContaining('Losartan 50mg 1 tablet, twice daily ×60'), findsOneWidget);
    expect(find.textContaining('payment paid'), findsOneWidget);
    await t.tap(find.byKey(const Key('message-patient')));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('pharmacy-chat-input')), findsOneWidget);
  });

  tallTest('patient writes to the pharmacy', (t) async {
    repo.chat = [
      PharmacyMessage(
        id: 'm1',
        patientId: 'u-patient',
        senderRole: 'pharmacist',
        senderName: 'Harvey Pharmacy (Ahmad)',
        text: 'Your refill is ready.',
        sentAt: DateTime.utc(2026, 10, 16, 2),
      ),
    ];
    await t.pumpWidget(host('/pharmacy-chat'));
    await t.pumpAndSettle();
    expect(find.text('Your refill is ready.'), findsOneWidget);
    expect(find.textContaining('call 999'), findsOneWidget);
    await t.enterText(find.byKey(const Key('pharmacy-chat-input')), 'Thank you!');
    await t.tap(find.byKey(const Key('pharmacy-chat-send')));
    await t.pumpAndSettle();
    expect(repo.calls, contains('toPharmacy:Thank you!'));
  });

  tallTest('pharmacist inbox opens a conversation and replies', (t) async {
    final last = PharmacyMessage(
      id: 'm2',
      patientId: 'u-patient',
      senderRole: 'patient',
      senderName: 'Siti',
      text: 'When is my order ready?',
      sentAt: DateTime.utc(2026, 10, 16, 2),
    );
    repo
      ..conversations = [PharmacyConversation(last: last, patientName: 'Siti')]
      ..chat = [last];
    await t.pumpWidget(host('/pharmacy/messages'));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('conversation-u-patient')));
    await t.pumpAndSettle();
    await t.enterText(find.byKey(const Key('pharmacy-chat-input')), 'Tomorrow at 10 AM.');
    await t.tap(find.byKey(const Key('pharmacy-chat-send')));
    await t.pumpAndSettle();
    expect(repo.calls, contains('toPatient:u-patient:Tomorrow at 10 AM.'));
  });

  // ---------------- D-70 ----------------

  tallTest('D-70 tracking filters orders by stage and opens the patient', (t) async {
    repo.overviewData = OrdersOverview(
      orders: [itemOrder(status: Fulfilment.preparing, paymentStatus: 'paid')],
      counts: const {'in_pharmacy': 1, 'completed': 2},
    );
    await t.pumpWidget(host('/pharmacy/tracking'));
    await t.pumpAndSettle();
    expect(find.text('All (3)'), findsOneWidget);
    expect(find.text('In pharmacy (1)'), findsOneWidget);
    expect(find.text('CF-ABC123'), findsOneWidget);
    await t.tap(find.byKey(const Key('group-completed')));
    await t.pumpAndSettle();
    expect(repo.calls, contains('overview:completed:'));
    await t.enterText(find.byKey(const Key('tracking-search')), 'siti');
    await t.testTextInput.receiveAction(TextInputAction.done);
    await t.pumpAndSettle();
    expect(repo.calls, contains('overview:completed:siti'));
    repo.patientDetail = const PharmacyPatientDetail(id: 'u-patient', name: 'Siti Aminah');
    await t.tap(find.text('CF-ABC123'));
    await t.pumpAndSettle();
    expect(find.text('Siti Aminah'), findsOneWidget);
  });

  tallTest('D-70 patients tab lists every patient and opens one', (t) async {
    repo
      ..patients = const [
        PharmacyPatient(
          id: 'u-patient',
          name: 'Siti Aminah',
          email: 'siti@x.my',
          age: 58,
          gender: 'female',
          orderCount: 2,
          activeOrders: 1,
          regimen: [],
          recentOrders: [],
        ),
      ]
      ..patientDetail = const PharmacyPatientDetail(id: 'u-patient', name: 'Siti Aminah');
    await t.pumpWidget(host('/pharmacy/patients'));
    await t.pumpAndSettle();
    expect(find.text('58 · female'), findsOneWidget);
    await t.tap(find.text('siti@x.my'));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('back-to-patients')), findsOneWidget);
    expect(repo.calls, contains('patient:u-patient'));
  });

  tallTest('D-70 pharmacist starts a message with any patient', (t) async {
    repo.patients = const [
      PharmacyPatient(id: 'u-new', name: 'Ali', regimen: [], recentOrders: []),
    ];
    await t.pumpWidget(host('/pharmacy/messages'));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('new-message')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('pick-u-new')));
    await t.pumpAndSettle();
    await t.enterText(find.byKey(const Key('pharmacy-chat-input')), 'Hello Ali');
    await t.tap(find.byKey(const Key('pharmacy-chat-send')));
    await t.pumpAndSettle();
    expect(repo.calls, contains('toPatient:u-new:Hello Ali'));
  });

  tallTest('D-70 only the admin inventory can delete stock', (t) async {
    repo.stockItems = const [
      StockItem(id: 's1', name: 'Amlodipine 5mg', units: 600, lowStockAt: 50, low: false),
    ];
    await t.pumpWidget(host('/pharmacy/inventory'));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('stock-delete-s1')), findsNothing);
    await t.pumpWidget(host('/pharmacy/admin-inventory'));
    await t.pumpAndSettle();
    await t.ensureVisible(find.byKey(const Key('stock-delete-s1')));
    await t.tap(find.byKey(const Key('stock-delete-s1')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('stock-delete-confirm')));
    await t.pumpAndSettle();
    expect(repo.calls, contains('deleteStock:s1'));
  });

  tallTest('D-70 checkout shows the drop-off on an embedded map', (t) async {
    repo.orders = {id: itemOrder(suggestedAddress: '77 Lorong', lat: 5.4588, lng: 100.2886)};
    await t.pumpWidget(host('/orders/$id/confirm'));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('method-delivery')));
    await t.pumpAndSettle();
    expect(find.text('PREVIEW 5.4588,100.2886'), findsOneWidget);
  });

  tallTest('D-72 a paid order shows its estimated ready time', (t) async {
    repo.orders = {
      id: MedicationOrder.fromJson({
        'id': id,
        'ref': 'CF-ABC123',
        'patientId': 'u-patient',
        'prescriptionId': 'rx1',
        'medicationDetails': 'Amlodipine 5mg',
        'fulfilmentStatus': 'preparing',
        'paymentStatus': 'paid',
        'method': 'self_collection',
        'amount': 9,
        'total': 9,
        'paidAt': '2026-10-16T02:00:00+00:00',
        'estimatedReadyAt': '2026-10-16T04:00:00+00:00',
      }),
    };
    final router = GoRouter(
      initialLocation: '/t',
      routes: [
        GoRoute(
          path: '/t',
          builder: (_, _) => const OrderTrackPage(orderId: id),
        ),
      ],
    );
    await t.pumpWidget(
      ProviderScope(
        overrides: [ordersRepositoryProvider.overrideWithValue(repo)],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await t.pumpAndSettle();
    expect(find.textContaining('Estimated ready by 12:00 PM'), findsOneWidget);
  });

  tallTest('D-73 the pharmacy sees new prescriptions before the patient pays', (t) async {
    repo.overviewData = OrdersOverview(
      orders: [itemOrder()],
      counts: const {'awaiting_patient': 1},
    );
    await t.pumpWidget(host('/pharmacy'));
    await t.pumpAndSettle();
    expect(repo.calls, contains('overview:awaiting_patient:'));
    expect(find.byKey(const Key('incoming-$id')), findsOneWidget);
    expect(find.textContaining('Siti · Amlodipine 5mg ×30, Losartan 50mg ×60'), findsOneWidget);
    expect(find.textContaining('Waiting for you to confirm'), findsOneWidget);
  });

  tallTest('D-73 admin order detail shows medicines, payment, delivery and history', (t) async {
    repo.orders = {
      id: MedicationOrder.fromJson({
        'id': id,
        'ref': 'CF-ABC123',
        'patientId': 'u-patient',
        'patientName': 'Siti',
        'prescriptionId': 'rx1',
        'medicationDetails': 'x',
        'fulfilmentStatus': 'ready_for_delivery',
        'paymentStatus': 'paid',
        'method': 'home_delivery',
        'deliveryStatus': 'in_transit',
        'deliveryAddress': '25 Lintang Sungai Ara 6',
        'deliveryPhone': '0143997403',
        'courierRef': '3607496166784815549',
        'courierBrand': 'Lalamove',
        'trackingUrl': 'https://share.sandbox.lalamove.com?x',
        'amount': 63,
        'deliveryFee': 13.8,
        'total': 76.8,
        'paidAt': '2026-10-16T02:00:00+00:00',
        'items': [
          {
            'catalogId': 'amlodipine-5',
            'name': 'Amlodipine',
            'strength': '5mg',
            'dose': '1 tablet',
            'frequency': 'once_daily',
            'quantity': 30,
            'unitPrice': 0.3,
          },
        ],
        'events': [
          {'status': 'dispatched', 'timestamp': '2026-10-16T03:00:00+00:00'},
        ],
      }),
    };
    final router = GoRouter(
      initialLocation: '/o',
      routes: [
        GoRoute(
          path: '/o',
          builder: (_, _) => const Scaffold(
            body: StaffOrderPage(orderId: id, backPath: '/o', backLabel: 'Orders'),
          ),
        ),
      ],
    );
    await t.pumpWidget(
      ProviderScope(
        overrides: [ordersRepositoryProvider.overrideWithValue(repo)],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await t.pumpAndSettle();
    expect(find.text('Order CF-ABC123'), findsOneWidget);
    expect(find.text('1 tablet, once daily · 30 × RM0.30 = RM9.00'), findsOneWidget);
    expect(find.text('RM13.80'), findsOneWidget);
    expect(find.text('RM76.80'), findsOneWidget);
    expect(find.text('25 Lintang Sungai Ara 6'), findsOneWidget);
    expect(find.text('3607496166784815549'), findsOneWidget);
    expect(find.text('Courier: dispatched'), findsOneWidget);
    expect(find.byKey(const Key('staff-courier-tracking')), findsOneWidget);
  });

  tallTest('D-74 the pharmacy queue lists waiting prescriptions and can cancel them', (t) async {
    repo.overviewData = OrdersOverview(
      orders: [itemOrder()],
      counts: const {'awaiting_patient': 1},
    );
    await t.pumpWidget(host('/pharmacy'));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('waiting-for-patient')), findsOneWidget);
    await t.tap(find.byKey(const Key('cancel-$id')));
    await t.pumpAndSettle();
    await t.enterText(find.byKey(const Key('cancel-reason')), 'Doctor changed the regimen');
    await t.pump();
    await t.tap(find.byKey(const Key('cancel-confirm')));
    await t.pumpAndSettle();
    expect(repo.calls, contains('cancel:$id:Doctor changed the regimen'));
  });

  tallTest('D-74 a cancelled order moves to Completed with its reason', (t) async {
    repo.orders = {
      id: MedicationOrder.fromJson({
        'id': id,
        'ref': 'CF-ABC123',
        'patientId': 'u-patient',
        'prescriptionId': 'rx1',
        'medicationDetails': 'Amlodipine 5mg',
        'fulfilmentStatus': 'cancelled',
        'paymentStatus': 'pending',
        'cancelReason': 'Prescription stopped by your doctor.',
        'cancelledBy': 'doctor',
      }),
    };
    await t.pumpWidget(host('/orders'));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('order-$id')), findsNothing); // not under Active
    await t.tap(find.byKey(const Key('orders-tab-completed')));
    await t.pumpAndSettle();
    expect(find.text('Cancelled: Prescription stopped by your doctor.'), findsOneWidget);
  });
}
