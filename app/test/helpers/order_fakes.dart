import 'package:hypertension/features/family/data/location_source.dart';
import 'package:hypertension/features/orders/data/order_models.dart';
import 'package:hypertension/features/orders/data/orders_repository.dart';
import 'package:hypertension/features/orders/data/payment_sheet.dart';
import 'package:hypertension/shared/services/api/api_client.dart';

/// Module 13 test double (D-66): records calls and returns canned data.
class FakeOrdersRepository implements OrdersRepository {
  final calls = <String>[];
  Map<String, MedicationOrder> orders = {};
  PaymentStart payment = const PaymentStart(
    mode: 'fake',
    clientSecret: 'pi_fake_secret',
    publishableKey: '',
    amount: 15,
  );
  PaymentResult Function(String card) fakeCard = (card) =>
      card.replaceAll(' ', '') == '4000000000000002'
      ? const PaymentResult('failed', message: 'Your card was declined.')
      : const PaymentResult('paid');
  PaymentResult refreshResult = const PaymentResult('paid');
  PharmacyQueue queueData = const PharmacyQueue(orders: [], needsPrice: []);
  List<StockItem> stockItems = const [];
  List<PharmacyPatient> patients = const [];
  DeliveryOverview overview = const DeliveryOverview(
    orders: [],
    courier: 'Grab (simulated)',
    simulated: true,
  );
  ApiException? failNext;

  void _maybeFail() {
    final f = failNext;
    if (f != null) {
      failNext = null;
      throw f;
    }
  }

  @override
  Future<List<MedicationOrder>> myOrders() async => orders.values.toList();

  @override
  Future<MedicationOrder> order(String id) async => orders[id]!;

  @override
  Future<MedicationOrder> confirm(
    String id,
    String method, {
    String? address,
    double? lat,
    double? lng,
    String? phone,
  }) async {
    calls.add(
      'confirm:$id:$method:${address ?? ''}${lat == null ? '' : ':$lat,$lng:${phone ?? ''}'}',
    );
    _maybeFail();
    return orders[id]!;
  }

  @override
  Future<void> skip(String id) async => calls.add('skip:$id');

  /// D-71: the courier's quote returned to checkout.
  double quotedFee = 13.8;

  @override
  Future<double> deliveryQuote(
    String id, {
    required String address,
    required double lat,
    required double lng,
  }) async {
    calls.add('quote:$id:$lat,$lng');
    return quotedFee;
  }

  @override
  Future<PaymentStart> startPayment(String id) async {
    calls.add('pay:$id');
    return payment;
  }

  @override
  Future<PaymentResult> payFake(String id, String cardNumber) async {
    calls.add('payFake:$id:${cardNumber.replaceAll(' ', '')}');
    return fakeCard(cardNumber);
  }

  @override
  Future<PaymentResult> refreshPayment(String id) async {
    calls.add('refresh:$id');
    return refreshResult;
  }

  @override
  Future<void> reschedule(String id) async => calls.add('reschedule:$id');

  @override
  Future<void> switchToCollection(String id) async => calls.add('switch:$id');

  @override
  Future<int> devNextCycle() async {
    calls.add('devNextCycle');
    return 1;
  }

  @override
  Future<PharmacyQueue> queue() async => queueData;

  @override
  Future<void> setPrice(String prescriptionId, double price) async =>
      calls.add('price:$prescriptionId:$price');

  @override
  Future<void> markReady(String id, {String? stockItemId, int? units}) async {
    calls.add(stockItemId == null ? 'ready:$id' : 'ready:$id:$stockItemId:$units');
    _maybeFail();
  }

  @override
  Future<void> outOfStock(String id, {String? note}) async => calls.add('oos:$id:${note ?? ''}');

  @override
  Future<void> collected(String id) async => calls.add('collected:$id');

  @override
  Future<List<StockItem>> stock() async => stockItems;

  @override
  Future<void> addStock({
    required String name,
    required int units,
    required String expiryDate,
    required int lowStockAt,
    String? catalogId,
  }) async =>
      calls.add('addStock:$name:$units:$expiryDate${catalogId == null ? '' : ':$catalogId'}');

  @override
  Future<void> receiveStock(String id, int units, String expiryDate) async =>
      calls.add('receive:$id:$units:$expiryDate');

  @override
  Future<void> setLowStockAt(String id, int lowStockAt) async => calls.add('lowAt:$id:$lowStockAt');

  @override
  Future<List<PharmacyPatient>> lookup(String query) async {
    calls.add('lookup:$query');
    return patients;
  }

  // ---- D-69 ----
  List<CatalogItem> catalogItems = const [
    CatalogItem(
      id: 'amlodipine-5',
      name: 'Amlodipine',
      strength: '5mg',
      form: 'tablet',
      unitPrice: 0.30,
      drugClass: 'Calcium channel blocker',
    ),
    CatalogItem(
      id: 'losartan-50',
      name: 'Losartan',
      strength: '50mg',
      form: 'tablet',
      unitPrice: 0.90,
      drugClass: 'Angiotensin receptor blocker',
    ),
  ];
  PharmacyPatientDetail? patientDetail;
  List<PharmacyMessage> chat = [];
  List<PharmacyConversation> conversations = [];

  @override
  Future<List<CatalogItem>> catalog() async => catalogItems;

  @override
  Future<void> addCatalogItem({
    required String name,
    required String strength,
    required String form,
    required double unitPrice,
    String drugClass = '',
  }) async => calls.add('addCatalog:$name:$strength:$unitPrice');

  @override
  Future<void> setCatalogPrice(String id, double unitPrice) async =>
      calls.add('catalogPrice:$id:$unitPrice');

  @override
  Future<void> editCatalogItem(
    String id, {
    String? name,
    String? strength,
    String? drugClass,
    String? form,
    double? unitPrice,
    bool? active,
  }) async => calls.add(
    'editCatalog:$id:${name ?? ''}:${strength ?? ''}:${unitPrice ?? ''}:${active ?? ''}',
  );

  @override
  Future<void> deleteStock(String id) async => calls.add('deleteStock:$id');

  OrdersOverview overviewData = const OrdersOverview(orders: [], counts: {});

  @override
  Future<OrdersOverview> ordersOverview({String group = 'all', String query = ''}) async {
    calls.add('overview:$group:$query');
    return overviewData;
  }

  @override
  Future<PharmacyPatientDetail> pharmacyPatient(String uid) async {
    calls.add('patient:$uid');
    return patientDetail!;
  }

  @override
  Future<List<PharmacyMessage>> myPharmacyChat() async => chat;

  @override
  Future<void> sendToPharmacy(String text) async => calls.add('toPharmacy:$text');

  @override
  Future<List<PharmacyConversation>> pharmacyConversations() async => conversations;

  @override
  Future<({String patientName, List<PharmacyMessage> messages})> pharmacyThread(String uid) async =>
      (patientName: 'Siti', messages: chat);

  @override
  Future<void> sendToPatient(String uid, String text) async => calls.add('toPatient:$uid:$text');

  @override
  Future<void> saveAddress(String address, {double? lat, double? lng}) async =>
      calls.add('address:$address:$lat,$lng');

  @override
  Future<DeliveryOverview> deliveries() async => overview;

  Map<String, dynamic> courier = const {
    'provider': 'Lalamove',
    'name': 'Lalamove (sandbox, driver simulated)',
    'simulated': false,
    'pickupAddress': '77, Lorong Lembah Permai Tiga, Tanjung Bungah',
    'pickupPhone': '+60143997403',
    'webhookUrl': 'https://hypertension-dd85f.web.app/api/v1/webhooks/lalamove',
    'keysConfigured': true,
  };

  @override
  Future<Map<String, dynamic>> courierSettings() async => courier;

  @override
  Future<void> dispatch(String id) async => calls.add('dispatch:$id');

  @override
  Future<void> simulateFailure(String id) async => calls.add('fail:$id');
}

class FakePaymentSheet implements PaymentSheetLauncher {
  SheetResult result = const SheetResult(SheetOutcome.completed);
  final presented = <String>[];

  @override
  Future<SheetResult> present({
    required String publishableKey,
    required String clientSecret,
  }) async {
    presented.add('$publishableKey|$clientSecret');
    return result;
  }
}

MedicationOrder anOrder({
  String id = 'rx1_2026-10',
  Fulfilment status = Fulfilment.awaitingConfirmation,
  double? amount = 15,
  String? method,
  String paymentStatus = 'pending',
  String? deliveryStatus,
  String? courierRef,
  String? failureReason,
  DateTime? etaAt,
  DateTime? readyAt,
  String? patientName = 'Siti',
  List<TrackingEvent> events = const [],
}) => MedicationOrder(
  id: id,
  ref: 'CF-ABC123',
  patientId: 'u-patient',
  patientName: patientName,
  prescriptionId: 'rx1',
  medicationDetails: 'Amlodipine 5mg, once daily',
  status: status,
  paymentStatus: paymentStatus,
  method: method,
  deliveryStatus: deliveryStatus,
  amount: amount,
  deliveryFee: method == homeDelivery ? 5 : 0,
  total: amount == null ? null : amount + (method == homeDelivery ? 5 : 0),
  courierRef: courierRef,
  failureReason: failureReason,
  cycleDate: DateTime.utc(2026, 10, 16, 2),
  paidAt: paymentStatus == 'paid' ? DateTime.utc(2026, 10, 16, 5, 15) : null,
  readyAt: readyAt,
  dispatchedAt: deliveryStatus == null ? null : DateTime.utc(2026, 10, 16, 6),
  etaAt: etaAt,
  events: events,
);

/// D-67: the phone's GPS for the delivery drop-off.
class FakeOrderLocation implements LocationSource {
  Map<String, double>? here = {'lat': 3.1579, 'lng': 101.7123};
  LocationAccess access = LocationAccess.granted;
  final settings = <LocationAccess>[];

  @override
  Future<Map<String, double>?> current({bool ask = false}) async => here;

  @override
  Future<bool> granted() async => access == LocationAccess.granted;

  @override
  Future<LocationAccess> request() async => access;

  @override
  Future<void> openSettings(LocationAccess access) async => settings.add(access);
}
