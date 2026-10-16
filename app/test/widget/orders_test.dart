import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hypertension/features/family/data/location_source.dart';
import 'package:hypertension/features/family/state/family_providers.dart';
import 'package:hypertension/features/orders/data/order_models.dart';
import 'package:hypertension/features/orders/data/payment_sheet.dart';
import 'package:hypertension/features/orders/presentation/admin_deliveries_page.dart';
import 'package:hypertension/features/orders/presentation/order_confirm_page.dart';
import 'package:hypertension/features/orders/presentation/order_pay_page.dart';
import 'package:hypertension/features/orders/presentation/order_track_page.dart';
import 'package:hypertension/features/orders/presentation/order_widgets.dart';
import 'package:hypertension/features/orders/presentation/orders_page.dart';
import 'package:hypertension/features/orders/presentation/pharmacy_page.dart';
import 'package:hypertension/features/orders/state/orders_providers.dart';
import 'package:hypertension/shared/services/api/api_client.dart';

import '../helpers/fakes.dart';
import '../helpers/order_fakes.dart';
import 'package:hypertension/features/orders/presentation/inventory_page.dart';
import 'package:hypertension/features/orders/presentation/pharmacy_patients_page.dart';

// Module 13: recurring orders, payment and delivery (FR-13.1-13.5; UC13.1-UC13.6; D-66).

late FakeOrdersRepository repo;
late FakePaymentSheet sheet;
late FakeOrderLocation location;

const id = 'rx1_2026-10';

Widget host(String initial) {
  final router = GoRouter(
    initialLocation: initial,
    routes: [
      GoRoute(
        path: '/home',
        builder: (_, _) => const Scaffold(body: Column(children: [MonthlyOrdersBanner()])),
      ),
      GoRoute(path: '/orders', builder: (_, _) => const OrdersPage()),
      GoRoute(
        path: '/orders/:id/confirm',
        builder: (_, s) => OrderConfirmPage(orderId: s.pathParameters['id']!),
      ),
      GoRoute(
        path: '/orders/:id/pay',
        builder: (_, s) => OrderPayPage(orderId: s.pathParameters['id']!),
      ),
      GoRoute(
        path: '/orders/:id/track',
        builder: (_, s) => OrderTrackPage(orderId: s.pathParameters['id']!),
      ),
      GoRoute(
        path: '/pharmacy',
        builder: (_, _) => const Scaffold(body: PharmacyPage()),
      ),
      // D-70: inventory and patients have their own tabs.
      GoRoute(
        path: '/pharmacy/inventory',
        builder: (_, _) => const Scaffold(body: InventoryPage()),
      ),
      GoRoute(
        path: '/pharmacy/patients',
        builder: (_, _) => const Scaffold(body: PharmacyPatientsPage()),
      ),
      GoRoute(
        path: '/admin/deliveries',
        builder: (_, _) => const Scaffold(body: AdminDeliveriesPage()),
      ),
    ],
  );
  return ProviderScope(
    overrides: [
      ordersRepositoryProvider.overrideWithValue(repo),
      paymentSheetProvider.overrideWithValue(sheet),
      mapBuilderProvider.overrideWithValue((lat, lng, label) => Text('MAP $lat,$lng')),
      locationSourceProvider.overrideWithValue(location),
    ],
    child: MaterialApp.router(routerConfig: router),
  );
}

void main() {
  setUp(() {
    repo = FakeOrdersRepository();
    sheet = FakePaymentSheet();
    location = FakeOrderLocation();
  });

  group('UC13.2 entry and order list', () {
    tallTest('meds banner points to the order that needs the patient', (t) async {
      repo.orders = {id: anOrder()};
      await t.pumpWidget(host('/home'));
      await t.pumpAndSettle();
      expect(find.text('Your monthly order needs you'), findsOneWidget);
      await t.tap(find.byKey(const Key('orders-banner')));
      await t.pumpAndSettle();
      expect(find.text('Confirm monthly order'), findsOneWidget);
    });

    tallTest('no orders: no banner', (t) async {
      await t.pumpWidget(host('/home'));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('orders-banner')), findsNothing);
    });

    tallTest('order list shows month, status and total', (t) async {
      repo.orders = {
        id: anOrder(status: Fulfilment.preparing, paymentStatus: 'paid', method: homeDelivery),
      };
      await t.pumpWidget(host('/orders'));
      await t.pumpAndSettle();
      expect(find.text('October 2026'), findsOneWidget);
      expect(find.text('Preparing'), findsOneWidget);
      expect(find.textContaining('RM20.00'), findsOneWidget);
      expect(find.textContaining('Home delivery'), findsOneWidget);
    });

    tallTest('D-66 testing aid starts next month', (t) async {
      await t.pumpWidget(host('/orders'));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('orders-empty')), findsOneWidget);
      await t.tap(find.byKey(const Key('orders-menu')));
      await t.pumpAndSettle();
      await t.tap(find.text("Start next month's order (testing)"));
      await t.pumpAndSettle();
      expect(repo.calls, contains('devNextCycle'));
    });
  });

  group('Fig 4.3.10.1 order confirmation (UC13.3)', () {
    tallTest('self-collection total, confirm then go to payment', (t) async {
      repo.orders = {id: anOrder()};
      await t.pumpWidget(host('/orders/$id/confirm'));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('item-price')), findsOneWidget);
      expect(
        t.widget<FilledButton>(find.byKey(const Key('confirm-order'))).onPressed,
        isNull,
      ); // no method yet
      await t.tap(find.byKey(const Key('method-collection')));
      await t.pumpAndSettle();
      expect(
        find.descendant(of: find.byKey(const Key('order-total')), matching: find.text('RM15.00')),
        findsNothing,
      );
      expect(find.byKey(const Key('order-total')), findsOneWidget);
      expect(t.widget<Text>(find.byKey(const Key('order-total'))).data, 'RM15.00');
      await t.tap(find.byKey(const Key('confirm-order')));
      await t.pumpAndSettle();
      expect(repo.calls, contains('confirm:$id:self_collection:'));
      expect(find.text('Payment'), findsOneWidget);
    });

    tallTest('D-67 home delivery adds RM5 and needs address, location and phone', (t) async {
      repo.orders = {
        id: MedicationOrder.fromJson({
          'id': id,
          'ref': 'CF-ABC123',
          'patientId': 'u-patient',
          'prescriptionId': 'rx1',
          'medicationDetails': 'Amlodipine 5mg',
          'fulfilmentStatus': 'awaiting_confirmation',
          'paymentStatus': 'pending',
          'amount': 15,
          'suggestedPhone': '012-345 6789',
        }),
      };
      await t.pumpWidget(host('/orders/$id/confirm'));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('method-delivery')));
      await t.pumpAndSettle();
      expect(t.widget<Text>(find.byKey(const Key('order-total'))).data, 'RM20.00');
      await t.tap(find.byKey(const Key('confirm-order')));
      await t.pumpAndSettle();
      expect(find.text('Enter the delivery address.'), findsOneWidget);
      await t.enterText(find.byKey(const Key('delivery-address')), '12 Jalan Ampang');
      await t.tap(find.byKey(const Key('confirm-order')));
      await t.pumpAndSettle();
      expect(find.textContaining('Share your current location'), findsOneWidget);
      // Contact number is prefilled from the profile.
      expect(find.text('012-345 6789'), findsOneWidget);
      await t.tap(find.byKey(const Key('use-location')));
      await t.pumpAndSettle();
      expect(find.text('Location shared for the courier'), findsOneWidget);
      await t.tap(find.byKey(const Key('confirm-order')));
      await t.pumpAndSettle();
      expect(
        repo.calls,
        contains('confirm:$id:home_delivery:12 Jalan Ampang:3.1579,101.7123:012-345 6789'),
      );
    });

    tallTest('D-67 location refused: explains and opens settings', (t) async {
      repo.orders = {id: anOrder()};
      location
        ..here = null
        ..access = LocationAccess.deniedForever;
      await t.pumpWidget(host('/orders/$id/confirm'));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('method-delivery')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('use-location')));
      await t.pumpAndSettle();
      expect(find.textContaining('Location permission was refused'), findsOneWidget);
      await t.tap(find.byKey(const Key('use-location')));
      await t.pumpAndSettle();
      expect(location.settings, [LocationAccess.deniedForever]);
    });

    tallTest('unpriced order cannot be confirmed', (t) async {
      repo.orders = {id: anOrder(amount: null)};
      await t.pumpWidget(host('/orders/$id/confirm'));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('not-priced')), findsOneWidget);
      await t.tap(find.byKey(const Key('method-collection')));
      await t.pumpAndSettle();
      expect(t.widget<FilledButton>(find.byKey(const Key('confirm-order'))).onPressed, isNull);
    });

    tallTest('UC13.2 A1 skip this month', (t) async {
      repo.orders = {id: anOrder()};
      await t.pumpWidget(host('/orders'));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('order-$id')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('skip-order')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('confirm-skip')));
      await t.pumpAndSettle();
      expect(repo.calls, contains('skip:$id'));
    });
  });

  group('Fig 4.3.10.2 payment (UC13.3; NFR-2.3)', () {
    tallTest('simulated card pays and opens tracking', (t) async {
      repo.orders = {id: anOrder(status: Fulfilment.awaitingPayment, method: selfCollection)};
      await t.pumpWidget(host('/orders/$id/pay'));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('fake-card-form')), findsOneWidget);
      expect(find.textContaining('Never enter a real card'), findsOneWidget);
      expect(t.widget<Text>(find.byKey(const Key('pay-total'))).data, 'RM15.00');
      repo.orders = {
        id: anOrder(status: Fulfilment.preparing, paymentStatus: 'paid', method: selfCollection),
      };
      await t.tap(find.byKey(const Key('pay-button')));
      await t.pumpAndSettle();
      expect(repo.calls, contains('payFake:$id:4242424242424242'));
      expect(find.text('Preparing your order'), findsOneWidget);
    });

    tallTest('UC13.3 E1 declined card stays and asks for another method', (t) async {
      repo.orders = {id: anOrder(status: Fulfilment.awaitingPayment, method: selfCollection)};
      await t.pumpWidget(host('/orders/$id/pay'));
      await t.pumpAndSettle();
      await t.enterText(find.byKey(const Key('card-number')), '4000 0000 0000 0002');
      await t.tap(find.byKey(const Key('pay-button')));
      await t.pumpAndSettle();
      expect(find.text('Your card was declined. Try another payment method.'), findsOneWidget);
      expect(find.text('Payment'), findsOneWidget);
    });

    tallTest('Stripe mode opens the PaymentSheet and checks the result', (t) async {
      repo
        ..orders = {id: anOrder(status: Fulfilment.awaitingPayment, method: selfCollection)}
        ..payment = const PaymentStart(
          mode: 'stripe',
          clientSecret: 'pi_1_secret',
          publishableKey: 'pk_test_1',
          amount: 15,
        );
      await t.pumpWidget(host('/orders/$id/pay'));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('stripe-method')), findsOneWidget);
      repo.orders = {
        id: anOrder(status: Fulfilment.preparing, paymentStatus: 'paid', method: selfCollection),
      };
      await t.tap(find.byKey(const Key('pay-button')));
      await t.pumpAndSettle();
      expect(sheet.presented, ['pk_test_1|pi_1_secret']);
      expect(repo.calls, contains('refresh:$id'));
      expect(find.text('Preparing your order'), findsOneWidget);
    });

    tallTest('cancelling the PaymentSheet does nothing', (t) async {
      repo
        ..orders = {id: anOrder(status: Fulfilment.awaitingPayment, method: selfCollection)}
        ..payment = const PaymentStart(
          mode: 'stripe',
          clientSecret: 's',
          publishableKey: 'pk_test_1',
          amount: 15,
        );
      sheet.result = const SheetResult(SheetOutcome.cancelled);
      await t.pumpWidget(host('/orders/$id/pay'));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('pay-button')));
      await t.pumpAndSettle();
      expect(repo.calls.where((c) => c.startsWith('refresh')), isEmpty);
      expect(find.byKey(const Key('pay-error')), findsNothing);
    });
  });

  group('Fig 4.3.10.3 tracking (UC13.4, UC13.5, FR-13.5)', () {
    tallTest('home delivery out for delivery with ETA and four stages', (t) async {
      repo.orders = {
        id: anOrder(
          status: Fulfilment.readyForDelivery,
          paymentStatus: 'paid',
          method: homeDelivery,
          deliveryStatus: 'in_transit',
          courierRef: 'GRB-8492',
          etaAt: DateTime.utc(2026, 10, 16, 6, 30),
        ),
      };
      await t.pumpWidget(host('/orders/$id/track'));
      await t.pumpAndSettle();
      expect(find.text('Out for delivery'), findsWidgets);
      expect(t.widget<Text>(find.byKey(const Key('eta'))).data, '2:30 PM');
      for (final s in ['Order confirmed', 'Preparing', 'Out for delivery', 'Delivered']) {
        expect(find.text(s), findsWidgets);
      }
      expect(find.textContaining('GRB-8492'), findsWidgets);
    });

    tallTest('D-68 courier name and its tracking page', (t) async {
      final opened = <Uri>[];
      repo.orders = {
        id: MedicationOrder.fromJson({
          'id': id,
          'ref': 'CF-ABC123',
          'patientId': 'u-patient',
          'prescriptionId': 'rx1',
          'medicationDetails': 'Amlodipine 5mg',
          'fulfilmentStatus': 'ready_for_delivery',
          'paymentStatus': 'paid',
          'method': 'home_delivery',
          'deliveryStatus': 'dispatched',
          'courierRef': '3607496166784815293',
          'courierBrand': 'Lalamove',
          'trackingUrl': 'https://share.sandbox.lalamove.com?MY100',
          'amount': 15,
          'deliveryFee': 5,
          'total': 20,
        }),
      };
      await t.pumpWidget(
        ProviderScope(
          overrides: [
            ordersRepositoryProvider.overrideWithValue(repo),
            openUrlProvider.overrideWithValue((u) async {
              opened.add(u);
              return true;
            }),
          ],
          child: MaterialApp(home: OrderTrackPage(orderId: id)),
        ),
      );
      await t.pumpAndSettle();
      expect(find.text('Lalamove booking 3607496166784815293'), findsOneWidget);
      await t.tap(find.byKey(const Key('courier-tracking')));
      await t.pumpAndSettle();
      expect(opened.single.host, 'share.sandbox.lalamove.com');
    });

    tallTest('self-collection shows the collection slip', (t) async {
      repo.orders = {
        id: anOrder(
          status: Fulfilment.readyForCollection,
          paymentStatus: 'paid',
          method: selfCollection,
          readyAt: DateTime.utc(2026, 10, 16, 7),
        ),
      };
      await t.pumpWidget(host('/orders/$id/track'));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('collection-slip')), findsOneWidget);
      expect(find.text('Prescription ID: rx1'), findsOneWidget);
      expect(find.textContaining('Ready since 3:00 PM'), findsOneWidget);
    });

    tallTest('FR-13.5 failed delivery offers reschedule and switch', (t) async {
      repo.orders = {
        id: anOrder(
          status: Fulfilment.failed,
          paymentStatus: 'paid',
          method: homeDelivery,
          deliveryStatus: 'failed',
          failureReason: 'The courier could not reach the address.',
        ),
      };
      await t.pumpWidget(host('/orders/$id/track'));
      await t.pumpAndSettle();
      expect(find.text('Delivery problem'), findsOneWidget);
      expect(find.text('The courier could not reach the address.'), findsOneWidget);
      await t.tap(find.byKey(const Key('reschedule-delivery')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('switch-collection')));
      await t.pumpAndSettle();
      expect(repo.calls, containsAll(['reschedule:$id', 'switch:$id']));
    });

    tallTest('UC13.6 E1 out of stock tells the patient about the delay', (t) async {
      repo.orders = {
        id: anOrder(status: Fulfilment.outOfStock, paymentStatus: 'paid', method: selfCollection),
      };
      await t.pumpWidget(host('/orders/$id/track'));
      await t.pumpAndSettle();
      expect(find.text('Your order is delayed'), findsOneWidget);
    });
  });

  group('Fig 4.3.13.1 pharmacist view (UC13.6)', () {
    const stock = StockItem(
      id: 's1',
      name: 'Amlodipine 5mg',
      units: 100,
      lowStockAt: 50,
      low: false,
    );

    tallTest('mark a paid order ready from stock', (t) async {
      repo
        ..queueData = PharmacyQueue(
          orders: [
            anOrder(status: Fulfilment.preparing, paymentStatus: 'paid', method: selfCollection),
          ],
          needsPrice: const [],
        )
        ..stockItems = const [stock];
      await t.pumpWidget(host('/pharmacy'));
      await t.pumpAndSettle();
      expect(find.textContaining('Siti · Amlodipine'), findsOneWidget);
      await t.tap(find.byKey(const Key('ready-$id')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('ready-confirm')));
      await t.pumpAndSettle();
      expect(repo.calls, contains('ready:$id:s1:30'));
    });

    tallTest('UC13.6 E1 out of stock with a note', (t) async {
      repo.queueData = PharmacyQueue(
        orders: [
          anOrder(status: Fulfilment.preparing, paymentStatus: 'paid', method: homeDelivery),
        ],
        needsPrice: const [],
      );
      await t.pumpWidget(host('/pharmacy'));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('oos-$id')));
      await t.pumpAndSettle();
      await t.enterText(find.byKey(const Key('oos-note')), 'Supplier delay');
      await t.tap(find.byKey(const Key('oos-confirm')));
      await t.pumpAndSettle();
      expect(repo.calls, contains('oos:$id:Supplier delay'));
    });

    tallTest('price a recurring prescription', (t) async {
      repo.queueData = const PharmacyQueue(
        orders: [],
        needsPrice: [
          UnpricedPrescription(id: 'rx9', medicationDetails: 'Losartan 50mg', patientName: 'Ali'),
        ],
      );
      await t.pumpWidget(host('/pharmacy'));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('queue-empty')), findsOneWidget);
      await t.tap(find.byKey(const Key('price-rx9')));
      await t.pumpAndSettle();
      await t.enterText(find.byKey(const Key('price-input')), '12.5');
      await t.pump();
      await t.tap(find.byKey(const Key('price-save')));
      await t.pumpAndSettle();
      expect(repo.calls, contains('price:rx9:12.5'));
    });

    tallTest('stock list warns when low; collected action', (t) async {
      repo
        ..stockItems = const [
          StockItem(
            id: 's2',
            name: 'Losartan 50mg',
            units: 45,
            lowStockAt: 50,
            low: true,
            expiryDate: '2027-01-31',
          ),
        ]
        ..queueData = PharmacyQueue(
          orders: [
            anOrder(
              status: Fulfilment.readyForCollection,
              paymentStatus: 'paid',
              method: selfCollection,
            ),
          ],
          needsPrice: const [],
        );
      await t.pumpWidget(host('/pharmacy/inventory'));
      await t.pumpAndSettle();
      expect(find.text('Low (< 50)'), findsOneWidget);
      expect(find.text('2027-01-31'), findsOneWidget);
      await t.pumpWidget(host('/pharmacy'));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('collected-$id')));
      await t.pumpAndSettle();
      expect(repo.calls, contains('collected:$id'));
    });

    tallTest('mark ready error is shown', (t) async {
      repo
        ..queueData = PharmacyQueue(
          orders: [
            anOrder(status: Fulfilment.preparing, paymentStatus: 'paid', method: selfCollection),
          ],
          needsPrice: const [],
        )
        ..stockItems = const [stock]
        ..failNext = ApiException('INSUFFICIENT_STOCK', 'Not enough units in stock.');
      await t.pumpWidget(host('/pharmacy'));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('ready-$id')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('ready-confirm')));
      await t.pumpAndSettle();
      expect(find.text('Not enough units in stock.'), findsOneWidget);
    });

    tallTest('patient lookup shows regimen', (t) async {
      repo.patients = const [
        PharmacyPatient(
          id: 'u-patient',
          name: 'Siti',
          regimen: [RegimenItem(id: 'rx1', medicationDetails: 'Amlodipine 5mg', monthlyPrice: 15)],
          recentOrders: [],
        ),
      ];
      // D-70: the Patients tab lists every patient and searches.
      await t.pumpWidget(host('/pharmacy/patients'));
      await t.pumpAndSettle();
      expect(repo.calls, contains('lookup:'));
      expect(find.text('Siti'), findsOneWidget);
      await t.enterText(find.byKey(const Key('patients-search')), 'siti');
      await t.testTextInput.receiveAction(TextInputAction.done);
      await t.pumpAndSettle();
      expect(repo.calls, contains('lookup:siti'));
    });
  });

  group('Fig 4.3.14.4 delivery oversight (FR-11.4)', () {
    tallTest('lists deliveries, flags out of stock, dispatch and simulate failure', (t) async {
      repo.overview = DeliveryOverview(
        courier: 'Grab (simulated)',
        simulated: true,
        orders: [
          anOrder(
            status: Fulfilment.readyForDelivery,
            paymentStatus: 'paid',
            method: homeDelivery,
            deliveryStatus: 'dispatched',
            courierRef: 'GRB-1',
          ),
          anOrder(
            id: 'rx2_2026-10',
            status: Fulfilment.failed,
            paymentStatus: 'paid',
            method: homeDelivery,
            deliveryStatus: 'failed',
          ),
          anOrder(
            id: 'rx3_2026-10',
            status: Fulfilment.outOfStock,
            paymentStatus: 'paid',
            method: selfCollection,
            patientName: 'Ali',
          ),
        ],
      );
      await t.pumpWidget(host('/admin/deliveries'));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('oos-flags')), findsOneWidget);
      expect(find.textContaining('Ali: Amlodipine'), findsOneWidget);
      expect(find.text('GRB-1'), findsOneWidget);
      await t.ensureVisible(find.byKey(const Key('simulate-fail-$id')));
      await t.tap(find.byKey(const Key('simulate-fail-$id')));
      await t.pumpAndSettle();
      await t.ensureVisible(find.byKey(const Key('dispatch-rx2_2026-10')));
      await t.tap(find.byKey(const Key('dispatch-rx2_2026-10')));
      await t.pumpAndSettle();
      expect(repo.calls, containsAll(['fail:$id', 'dispatch:rx2_2026-10']));
    });
  });
}
