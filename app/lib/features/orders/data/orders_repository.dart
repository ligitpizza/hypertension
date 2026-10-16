import '../../../shared/services/api/api_client.dart';
import 'order_models.dart';

/// Module 13 (FR-13.x; D-66). Orders are read through the API so the simulated courier
/// advances and totals come from one place.
abstract interface class OrdersRepository {
  Future<List<MedicationOrder>> myOrders();
  Future<MedicationOrder> order(String id);
  Future<MedicationOrder> confirm(
    String id,
    String method, {
    String? address,
    double? lat,
    double? lng,
    String? phone,
  });
  Future<void> skip(String id);

  /// D-71: the courier's fee in RM for this drop-off.
  Future<double> deliveryQuote(
    String id, {
    required String address,
    required double lat,
    required double lng,
  });
  Future<PaymentStart> startPayment(String id);
  Future<PaymentResult> payFake(String id, String cardNumber);
  Future<PaymentResult> refreshPayment(String id);
  Future<void> reschedule(String id);
  Future<void> switchToCollection(String id);
  Future<int> devNextCycle();

  Future<PharmacyQueue> queue();
  Future<void> setPrice(String prescriptionId, double price);

  /// Catalogue orders (D-69) take stock per item: leave [stockItemId] and [units] null.
  Future<void> markReady(String id, {String? stockItemId, int? units});
  Future<void> outOfStock(String id, {String? note});
  Future<void> collected(String id);

  /// D-74: cancel an unpaid order with a reason.
  Future<void> cancelOrder(String id, String reason);
  Future<List<StockItem>> stock();
  Future<void> addStock({
    required String name,
    required int units,
    required String expiryDate,
    required int lowStockAt,
    String? catalogId,
  });
  Future<void> receiveStock(String id, int units, String expiryDate);
  Future<void> setLowStockAt(String id, int lowStockAt);
  Future<List<PharmacyPatient>> lookup(String query);

  // D-69
  Future<List<CatalogItem>> catalog();
  Future<void> addCatalogItem({
    required String name,
    required String strength,
    required String form,
    required double unitPrice,
    String drugClass = '',
  });
  Future<void> setCatalogPrice(String id, double unitPrice);

  /// D-70: correct a catalogue medicine or (de)activate it.
  Future<void> editCatalogItem(
    String id, {
    String? name,
    String? strength,
    String? drugClass,
    String? form,
    double? unitPrice,
    bool? active,
  });
  Future<void> deleteStock(String id);
  Future<OrdersOverview> ordersOverview({String group = 'all', String query = ''});
  Future<PharmacyPatientDetail> pharmacyPatient(String uid);
  Future<List<PharmacyMessage>> myPharmacyChat();
  Future<void> sendToPharmacy(String text);
  Future<List<PharmacyConversation>> pharmacyConversations();
  Future<({String patientName, List<PharmacyMessage> messages})> pharmacyThread(String uid);
  Future<void> sendToPatient(String uid, String text);
  Future<void> saveAddress(String address, {double? lat, double? lng});

  Future<DeliveryOverview> deliveries();

  /// D-72: the courier as configured on the server (read-only).
  Future<Map<String, dynamic>> courierSettings();
  Future<void> dispatch(String id);
  Future<void> simulateFailure(String id);
}

class ApiOrdersRepository implements OrdersRepository {
  ApiOrdersRepository(this._api);
  final ApiClient _api;

  static List<MedicationOrder> _orders(Object? list) => [
    for (final o in (list as List? ?? const []))
      MedicationOrder.fromJson(Map<String, dynamic>.from(o as Map)),
  ];

  static PaymentResult _result(Map<String, dynamic> d) =>
      PaymentResult('${d['result']}', message: d['message'] as String?);

  @override
  Future<List<MedicationOrder>> myOrders() async => _orders((await _api.myOrders())['orders']);

  @override
  Future<MedicationOrder> order(String id) async => MedicationOrder.fromJson(await _api.order(id));

  @override
  Future<MedicationOrder> confirm(
    String id,
    String method, {
    String? address,
    double? lat,
    double? lng,
    String? phone,
  }) async => MedicationOrder.fromJson(
    await _api.confirmOrder(id, method, address: address, lat: lat, lng: lng, phone: phone),
  );

  @override
  Future<void> skip(String id) => _api.skipOrder(id);

  @override
  Future<double> deliveryQuote(
    String id, {
    required String address,
    required double lat,
    required double lng,
  }) async =>
      ((await _api.deliveryQuote(id, address: address, lat: lat, lng: lng))['deliveryFee'] as num)
          .toDouble();

  @override
  Future<PaymentStart> startPayment(String id) async =>
      PaymentStart.fromJson(await _api.startPayment(id));

  @override
  Future<PaymentResult> payFake(String id, String cardNumber) async =>
      _result(await _api.payFake(id, cardNumber));

  @override
  Future<PaymentResult> refreshPayment(String id) async => _result(await _api.refreshPayment(id));

  @override
  Future<void> reschedule(String id) => _api.rescheduleDelivery(id);

  @override
  Future<void> switchToCollection(String id) => _api.switchToCollection(id);

  @override
  Future<int> devNextCycle() async =>
      ((await _api.devNextOrderCycle())['created'] as List? ?? const []).length;

  @override
  Future<PharmacyQueue> queue() async {
    final d = await _api.pharmacyQueue();
    return PharmacyQueue(
      orders: _orders(d['orders']),
      needsPrice: [
        for (final r in (d['needsPrice'] as List? ?? const []))
          UnpricedPrescription.fromJson(Map<String, dynamic>.from(r as Map)),
      ],
    );
  }

  @override
  Future<void> setPrice(String prescriptionId, double price) =>
      _api.setMonthlyPrice(prescriptionId, price);

  @override
  Future<void> markReady(String id, {String? stockItemId, int? units}) =>
      _api.markOrderReady(id, stockItemId: stockItemId, units: units);

  @override
  Future<void> outOfStock(String id, {String? note}) => _api.markOutOfStock(id, note: note);

  @override
  Future<void> collected(String id) => _api.markCollected(id);

  @override
  Future<void> cancelOrder(String id, String reason) => _api.cancelOrder(id, reason);

  @override
  Future<List<StockItem>> stock() async => [
    for (final s in ((await _api.pharmacyStock())['items'] as List? ?? const []))
      StockItem.fromJson(Map<String, dynamic>.from(s as Map)),
  ];

  @override
  Future<void> addStock({
    required String name,
    required int units,
    required String expiryDate,
    required int lowStockAt,
    String? catalogId,
  }) => _api.addStockItem({
    'name': name,
    'catalogId': ?catalogId,
    'units': units,
    'expiryDate': expiryDate,
    'lowStockAt': lowStockAt,
  });

  @override
  Future<void> receiveStock(String id, int units, String expiryDate) =>
      _api.receiveStock(id, units, expiryDate);

  @override
  Future<void> setLowStockAt(String id, int lowStockAt) =>
      _api.editStockItem(id, {'lowStockAt': lowStockAt});

  @override
  Future<List<PharmacyPatient>> lookup(String query) async => [
    for (final p in ((await _api.pharmacyPatients(query))['patients'] as List? ?? const []))
      PharmacyPatient.fromJson(Map<String, dynamic>.from(p as Map)),
  ];

  static List<PharmacyMessage> _messages(Object? list) => [
    for (final m in (list as List? ?? const []))
      PharmacyMessage.fromJson(Map<String, dynamic>.from(m as Map)),
  ];

  @override
  Future<List<CatalogItem>> catalog() async => [
    for (final c in ((await _api.catalog())['items'] as List? ?? const []))
      CatalogItem.fromJson(Map<String, dynamic>.from(c as Map)),
  ];

  @override
  Future<void> addCatalogItem({
    required String name,
    required String strength,
    required String form,
    required double unitPrice,
    String drugClass = '',
  }) => _api.addCatalogItem({
    'name': name,
    'strength': strength,
    'form': form,
    'unitPrice': unitPrice,
    'drugClass': drugClass,
  });

  @override
  Future<void> setCatalogPrice(String id, double unitPrice) =>
      _api.editCatalogItem(id, {'unitPrice': unitPrice});

  @override
  Future<void> editCatalogItem(
    String id, {
    String? name,
    String? strength,
    String? drugClass,
    String? form,
    double? unitPrice,
    bool? active,
  }) => _api.editCatalogItem(id, {
    'name': ?name,
    'strength': ?strength,
    'drugClass': ?drugClass,
    'form': ?form,
    'unitPrice': ?unitPrice,
    'active': ?active,
  });

  @override
  Future<void> deleteStock(String id) => _api.deleteStockItem(id);

  @override
  Future<OrdersOverview> ordersOverview({String group = 'all', String query = ''}) async {
    final d = await _api.ordersOverview(group: group, query: query);
    return OrdersOverview(
      orders: _orders(d['orders']),
      counts: {
        for (final e in ((d['counts'] as Map?) ?? const {}).entries)
          '${e.key}': (e.value as num).toInt(),
      },
    );
  }

  @override
  Future<PharmacyPatientDetail> pharmacyPatient(String uid) async =>
      PharmacyPatientDetail.fromJson(await _api.pharmacyPatient(uid));

  @override
  Future<List<PharmacyMessage>> myPharmacyChat() async =>
      _messages((await _api.myPharmacyChat())['messages']);

  @override
  Future<void> sendToPharmacy(String text) => _api.sendPharmacyChat(text);

  @override
  Future<List<PharmacyConversation>> pharmacyConversations() async => [
    for (final c in ((await _api.pharmacyConversations())['conversations'] as List? ?? const []))
      PharmacyConversation(
        last: PharmacyMessage.fromJson(Map<String, dynamic>.from(c as Map)),
        patientName: c['patientName'] as String?,
      ),
  ];

  @override
  Future<({String patientName, List<PharmacyMessage> messages})> pharmacyThread(String uid) async {
    final d = await _api.pharmacyThread(uid);
    return (patientName: '${d['patientName'] ?? 'Patient'}', messages: _messages(d['messages']));
  }

  @override
  Future<void> sendToPatient(String uid, String text) => _api.sendPharmacyMessage(uid, text);

  @override
  Future<void> saveAddress(String address, {double? lat, double? lng}) =>
      _api.updateAddress(address, lat: lat, lng: lng);

  @override
  Future<DeliveryOverview> deliveries() async {
    final d = await _api.adminDeliveries();
    return DeliveryOverview(
      orders: _orders(d['orders']),
      courier: '${d['courier'] ?? 'Courier'}',
      simulated: d['simulated'] == true,
    );
  }

  @override
  Future<Map<String, dynamic>> courierSettings() => _api.adminCourier();

  @override
  Future<void> dispatch(String id) => _api.adminDispatch(id);

  @override
  Future<void> simulateFailure(String id) => _api.adminSimulateFailure(id);
}
