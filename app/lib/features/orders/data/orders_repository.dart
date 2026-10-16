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
  Future<PaymentStart> startPayment(String id);
  Future<PaymentResult> payFake(String id, String cardNumber);
  Future<PaymentResult> refreshPayment(String id);
  Future<void> reschedule(String id);
  Future<void> switchToCollection(String id);
  Future<int> devNextCycle();

  Future<PharmacyQueue> queue();
  Future<void> setPrice(String prescriptionId, double price);
  Future<void> markReady(String id, String stockItemId, int units);
  Future<void> outOfStock(String id, {String? note});
  Future<void> collected(String id);
  Future<List<StockItem>> stock();
  Future<void> addStock({
    required String name,
    required int units,
    required String expiryDate,
    required int lowStockAt,
  });
  Future<void> receiveStock(String id, int units, String expiryDate);
  Future<void> setLowStockAt(String id, int lowStockAt);
  Future<List<PharmacyPatient>> lookup(String query);

  Future<DeliveryOverview> deliveries();
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
  Future<void> markReady(String id, String stockItemId, int units) =>
      _api.markOrderReady(id, stockItemId, units);

  @override
  Future<void> outOfStock(String id, {String? note}) => _api.markOutOfStock(id, note: note);

  @override
  Future<void> collected(String id) => _api.markCollected(id);

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
  }) => _api.addStockItem({
    'name': name,
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
  Future<void> dispatch(String id) => _api.adminDispatch(id);

  @override
  Future<void> simulateFailure(String id) => _api.adminSimulateFailure(id);
}
