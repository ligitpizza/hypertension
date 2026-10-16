/// Module 13 views returned by the API (FR-13.x; D-66).
library;

DateTime? _time(Object? v) => v is String ? DateTime.tryParse(v)?.toLocal() : null;

double? _num(Object? v) => v is num ? v.toDouble() : null;

/// `medication_orders.fulfilmentStatus` (D-66).
enum Fulfilment {
  awaitingConfirmation('awaiting_confirmation', 'Waiting for you to confirm'),
  skipped('skipped', 'Skipped this month'),
  awaitingPayment('awaiting_payment', 'Waiting for payment'),
  preparing('preparing', 'Preparing'),
  outOfStock('out_of_stock', 'Delayed: out of stock'),
  readyForCollection('ready_for_collection', 'Ready for collection'),
  readyForDelivery('ready_for_delivery', 'Ready for delivery'),
  collected('collected', 'Collected'),
  delivered('delivered', 'Delivered'),
  failed('failed', 'Delivery failed');

  const Fulfilment(this.value, this.label);
  final String value;
  final String label;

  static Fulfilment fromValue(Object? v) =>
      values.firstWhere((f) => f.value == v, orElse: () => Fulfilment.awaitingConfirmation);
}

const selfCollection = 'self_collection';
const homeDelivery = 'home_delivery';

/// Flat home-delivery fee (D-66), shown before the patient confirms.
const deliveryFeeRm = 5.0;

String rm(num v) => 'RM${v.toStringAsFixed(2)}';

class TrackingEvent {
  const TrackingEvent({required this.status, this.location, this.timestamp});

  /// dispatched | picked_up | in_transit | delivered | failed
  final String status;
  final String? location;
  final DateTime? timestamp;

  factory TrackingEvent.fromJson(Map<String, dynamic> d) => TrackingEvent(
    status: '${d['status']}',
    location: d['location'] as String?,
    timestamp: _time(d['timestamp']),
  );
}

class MedicationOrder {
  const MedicationOrder({
    required this.id,
    required this.ref,
    required this.patientId,
    required this.prescriptionId,
    required this.medicationDetails,
    required this.status,
    required this.paymentStatus,
    this.patientName,
    this.method,
    this.deliveryStatus,
    this.amount,
    this.deliveryFee = 0,
    this.total,
    this.deliveryAddress,
    this.deliveryLat,
    this.deliveryLng,
    this.deliveryPhone,
    this.suggestedPhone,
    this.courierRef,
    this.failureReason,
    this.cycleDate,
    this.paidAt,
    this.readyAt,
    this.dispatchedAt,
    this.etaAt,
    this.events = const [],
  });

  final String id;

  /// Short reference shown to people, e.g. CF-3A9F1C.
  final String ref;
  final String patientId;
  final String? patientName;
  final String prescriptionId;
  final String medicationDetails;
  final Fulfilment status;

  /// pending | paid | failed
  final String paymentStatus;
  final String? method;

  /// dispatched | in_transit | delivered | failed
  final String? deliveryStatus;
  final double? amount;
  final double deliveryFee;
  final double? total;
  final String? deliveryAddress;

  /// D-67: drop-off point and contact number for the courier.
  final double? deliveryLat;
  final double? deliveryLng;
  final String? deliveryPhone;

  /// The patient's profile phone, to prefill the contact number (patient view only).
  final String? suggestedPhone;
  final String? courierRef;
  final String? failureReason;
  final DateTime? cycleDate;
  final DateTime? paidAt;
  final DateTime? readyAt;
  final DateTime? dispatchedAt;
  final DateTime? etaAt;
  final List<TrackingEvent> events;

  bool get isPriced => amount != null;
  bool get isDelivery => method == homeDelivery;
  bool get isPaid => paymentStatus == 'paid';
  bool get paymentFailed => paymentStatus == 'failed';

  /// The patient still has to act on it (confirm or pay).
  bool get needsPatient => switch (status) {
    Fulfilment.awaitingConfirmation || Fulfilment.awaitingPayment || Fulfilment.failed => true,
    _ => false,
  };

  /// Fig 4.3.10.3: Order Confirmed -> Preparing -> Out for Delivery -> Delivered (0-3).
  int get deliveryStage {
    if (status == Fulfilment.delivered) return 3;
    if (deliveryStatus == 'dispatched' || deliveryStatus == 'in_transit') return 2;
    return isPaid ? 1 : 0;
  }

  factory MedicationOrder.fromJson(Map<String, dynamic> d) => MedicationOrder(
    id: '${d['id']}',
    ref: '${d['ref'] ?? ''}',
    patientId: '${d['patientId'] ?? ''}',
    patientName: d['patientName'] as String?,
    prescriptionId: '${d['prescriptionId'] ?? ''}',
    medicationDetails: '${d['medicationDetails'] ?? 'Monthly prescription refill'}',
    status: Fulfilment.fromValue(d['fulfilmentStatus']),
    paymentStatus: '${d['paymentStatus'] ?? 'pending'}',
    method: d['method'] as String?,
    deliveryStatus: d['deliveryStatus'] as String?,
    amount: _num(d['amount']),
    deliveryFee: _num(d['deliveryFee']) ?? 0,
    total: _num(d['total']),
    deliveryAddress: d['deliveryAddress'] as String?,
    deliveryLat: _num(d['deliveryLat']),
    deliveryLng: _num(d['deliveryLng']),
    deliveryPhone: d['deliveryPhone'] as String?,
    suggestedPhone: d['suggestedPhone'] as String?,
    courierRef: d['courierRef'] as String?,
    failureReason: d['failureReason'] as String?,
    cycleDate: _time(d['cycleDate']),
    paidAt: _time(d['paidAt']),
    readyAt: _time(d['readyAt']),
    dispatchedAt: _time(d['dispatchedAt']),
    etaAt: _time(d['etaAt']),
    events: [
      for (final e in (d['events'] as List? ?? const []))
        TrackingEvent.fromJson(Map<String, dynamic>.from(e as Map)),
    ],
  );
}

/// A payment the app has to complete (UC13.3).
class PaymentStart {
  const PaymentStart({
    required this.mode,
    required this.clientSecret,
    required this.publishableKey,
    required this.amount,
  });

  /// stripe | fake
  final String mode;
  final String clientSecret;
  final String publishableKey;
  final double amount;

  bool get isFake => mode == 'fake';

  factory PaymentStart.fromJson(Map<String, dynamic> d) => PaymentStart(
    mode: '${d['mode']}',
    clientSecret: '${d['clientSecret'] ?? ''}',
    publishableKey: '${d['publishableKey'] ?? ''}',
    amount: _num(d['amount']) ?? 0,
  );
}

/// paid | failed | pending, with Stripe's decline message when failed.
class PaymentResult {
  const PaymentResult(this.result, {this.message});
  final String result;
  final String? message;

  bool get paid => result == 'paid';
}

class StockItem {
  const StockItem({
    required this.id,
    required this.name,
    required this.units,
    required this.lowStockAt,
    required this.low,
    this.expiryDate,
  });

  final String id;
  final String name;
  final int units;
  final int lowStockAt;
  final bool low;

  /// yyyy-MM-dd
  final String? expiryDate;

  factory StockItem.fromJson(Map<String, dynamic> d) => StockItem(
    id: '${d['id']}',
    name: '${d['name']}',
    units: (d['units'] as num?)?.toInt() ?? 0,
    lowStockAt: (d['lowStockAt'] as num?)?.toInt() ?? 50,
    low: d['low'] == true,
    expiryDate: d['expiryDate'] as String?,
  );
}

/// A recurring prescription waiting for its monthly price (D-66).
class UnpricedPrescription {
  const UnpricedPrescription({required this.id, required this.medicationDetails, this.patientName});

  final String id;
  final String medicationDetails;
  final String? patientName;

  factory UnpricedPrescription.fromJson(Map<String, dynamic> d) => UnpricedPrescription(
    id: '${d['id']}',
    medicationDetails: '${d['medicationDetails'] ?? ''}',
    patientName: d['patientName'] as String?,
  );
}

class PharmacyQueue {
  const PharmacyQueue({required this.orders, required this.needsPrice});
  final List<MedicationOrder> orders;
  final List<UnpricedPrescription> needsPrice;
}

class RegimenItem {
  const RegimenItem({required this.id, required this.medicationDetails, this.monthlyPrice});
  final String id;
  final String medicationDetails;
  final double? monthlyPrice;
}

/// Patient lookup row (Fig 4.3.13.1): regimen and recent orders only (D-66).
class PharmacyPatient {
  const PharmacyPatient({
    required this.id,
    required this.name,
    required this.regimen,
    required this.recentOrders,
    this.email,
    this.phone,
  });

  final String id;
  final String name;
  final String? email;
  final String? phone;
  final List<RegimenItem> regimen;
  final List<MedicationOrder> recentOrders;

  factory PharmacyPatient.fromJson(Map<String, dynamic> d) => PharmacyPatient(
    id: '${d['id']}',
    name: '${d['name'] ?? 'Patient'}',
    email: d['email'] as String?,
    phone: d['phone'] as String?,
    regimen: [
      for (final r in (d['regimen'] as List? ?? const []))
        RegimenItem(
          id: '${(r as Map)['id']}',
          medicationDetails: '${r['medicationDetails'] ?? ''}',
          monthlyPrice: _num(r['monthlyPrice']),
        ),
    ],
    recentOrders: [
      for (final o in (d['recentOrders'] as List? ?? const []))
        MedicationOrder.fromJson(Map<String, dynamic>.from(o as Map)),
    ],
  );
}

class DeliveryOverview {
  const DeliveryOverview({required this.orders, required this.courier, required this.simulated});
  final List<MedicationOrder> orders;
  final String courier;
  final bool simulated;
}
