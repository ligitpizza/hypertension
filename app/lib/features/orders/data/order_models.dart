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

/// Prescription frequencies (D-69), as the backend's catalogue FREQUENCIES.
const prescriptionFrequencies = {
  'once_daily': ('Once daily', 1),
  'twice_daily': ('Twice daily', 2),
  'three_times_daily': ('Three times daily', 3),
  'at_night': ('At night', 1),
  'as_needed': ('As needed', 0),
};

String frequencyLabel(String key) => prescriptionFrequencies[key]?.$1 ?? key;

/// One medicine in a consolidated prescription / order (D-69).
class OrderItem {
  const OrderItem({
    required this.name,
    required this.strength,
    required this.dose,
    required this.frequency,
    required this.quantity,
    required this.unitPrice,
    this.catalogId,
  });

  final String? catalogId;
  final String name;
  final String strength;
  final String dose;
  final String frequency;
  final int quantity;
  final double unitPrice;

  String get label => '$name $strength'.trim();
  double get lineTotal => double.parse((unitPrice * quantity).toStringAsFixed(2));

  factory OrderItem.fromJson(Map<String, dynamic> d) => OrderItem(
    catalogId: d['catalogId'] as String?,
    name: '${d['name'] ?? ''}',
    strength: '${d['strength'] ?? ''}',
    dose: '${d['dose'] ?? ''}',
    frequency: '${d['frequency'] ?? ''}',
    quantity: (d['quantity'] as num?)?.toInt() ?? 0,
    unitPrice: _num(d['unitPrice']) ?? 0,
  );
}

/// A `medication_catalog` entry (D-69).
class CatalogItem {
  const CatalogItem({
    required this.id,
    required this.name,
    required this.strength,
    required this.form,
    required this.unitPrice,
    this.drugClass = '',
    this.active = true,
  });

  final String id;
  final String name;
  final String strength;
  final String form;
  final String drugClass;
  final double unitPrice;
  final bool active;

  String get label => '$name $strength';

  factory CatalogItem.fromJson(Map<String, dynamic> d) => CatalogItem(
    id: '${d['id']}',
    name: '${d['name'] ?? ''}',
    strength: '${d['strength'] ?? ''}',
    form: '${d['form'] ?? 'tablet'}',
    drugClass: '${d['drugClass'] ?? ''}',
    unitPrice: _num(d['unitPrice']) ?? 0,
    active: d['active'] != false,
  );
}

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
    this.courierBrand = 'Lalamove',
    this.trackingUrl,
    this.failureReason,
    this.cycleDate,
    this.paidAt,
    this.readyAt,
    this.dispatchedAt,
    this.etaAt,
    this.events = const [],
    this.items = const [],
    this.suggestedAddress,
    this.suggestedLat,
    this.suggestedLng,
  });

  /// D-69: the consolidated prescription's medicines (empty for older orders).
  final List<OrderItem> items;

  /// The patient's saved address, to prefill checkout (patient view only).
  final String? suggestedAddress;
  final double? suggestedLat;
  final double? suggestedLng;

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

  /// D-68: the configured courier, for "delivered by Lalamove".
  final String courierBrand;

  /// The courier's live tracking page, when it gives one (Lalamove share link).
  final String? trackingUrl;
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
    courierBrand: d['courierBrand'] as String? ?? 'Lalamove',
    trackingUrl: d['trackingUrl'] as String?,
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
    items: [
      for (final i in (d['items'] as List? ?? const []))
        OrderItem.fromJson(Map<String, dynamic>.from(i as Map)),
    ],
    suggestedAddress: d['suggestedAddress'] as String?,
    suggestedLat: _num(d['suggestedLat']),
    suggestedLng: _num(d['suggestedLng']),
  );

  /// Active = still needs the patient, the pharmacy or the courier (Orders tabs, D-69).
  bool get isActive => switch (status) {
    Fulfilment.collected || Fulfilment.delivered || Fulfilment.skipped => false,
    _ => true,
  };
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
    this.gender,
    this.age,
    this.isActive = true,
    this.orderCount = 0,
    this.activeOrders = 0,
  });

  /// D-70 Patients tab.
  final String? gender;
  final int? age;
  final bool isActive;
  final int orderCount;
  final int activeOrders;

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
    gender: d['gender'] as String?,
    age: (d['age'] as num?)?.toInt(),
    isActive: d['isActive'] != false,
    orderCount: (d['orderCount'] as num?)?.toInt() ?? 0,
    activeOrders: (d['activeOrders'] as num?)?.toInt() ?? 0,
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

/// Pharmacist patient view (D-69): dispensing details only.
class PharmacyPatientDetail {
  const PharmacyPatientDetail({
    required this.id,
    required this.name,
    this.email,
    this.phone,
    this.gender,
    this.age,
    this.address,
    this.allergies = '',
    this.conditions = const [],
    this.medications = const [],
    this.prescriptions = const [],
    this.orders = const [],
  });

  final String id;
  final String name;
  final String? email;
  final String? phone;
  final String? gender;
  final int? age;
  final String? address;
  final String allergies;
  final List<String> conditions;
  final List<PatientMedicine> medications;
  final List<PatientPrescription> prescriptions;
  final List<MedicationOrder> orders;

  factory PharmacyPatientDetail.fromJson(Map<String, dynamic> d) => PharmacyPatientDetail(
    id: '${d['id']}',
    name: '${d['name'] ?? 'Patient'}',
    email: d['email'] as String?,
    phone: d['phone'] as String?,
    gender: d['gender'] as String?,
    age: (d['age'] as num?)?.toInt(),
    address: d['address'] as String?,
    allergies: '${d['allergies'] ?? ''}',
    conditions: [for (final c in (d['conditions'] as List? ?? const [])) '$c'],
    medications: [
      for (final m in (d['medications'] as List? ?? const []))
        PatientMedicine.fromJson(Map<String, dynamic>.from(m as Map)),
    ],
    prescriptions: [
      for (final p in (d['prescriptions'] as List? ?? const []))
        PatientPrescription.fromJson(Map<String, dynamic>.from(p as Map)),
    ],
    orders: [
      for (final o in (d['orders'] as List? ?? const []))
        MedicationOrder.fromJson(Map<String, dynamic>.from(o as Map)),
    ],
  );
}

class PatientMedicine {
  const PatientMedicine({
    required this.name,
    required this.dosage,
    required this.schedule,
    this.quantityOnHand,
    this.fromDoctor = false,
    this.prescribedBy,
  });

  final String name;
  final String dosage;
  final String schedule;
  final double? quantityOnHand;
  final bool fromDoctor;
  final String? prescribedBy;

  factory PatientMedicine.fromJson(Map<String, dynamic> d) => PatientMedicine(
    name: '${d['name'] ?? ''}',
    dosage: '${d['dosage'] ?? ''}',
    schedule: '${d['schedule'] ?? ''}',
    quantityOnHand: _num(d['quantityOnHand']),
    fromDoctor: d['source'] == 'doctor',
    prescribedBy: d['prescribedBy'] as String?,
  );
}

class PatientPrescription {
  const PatientPrescription({
    required this.id,
    required this.medicationDetails,
    this.items = const [],
    this.isRecurring = false,
    this.issuedAt,
  });

  final String id;
  final String medicationDetails;
  final List<OrderItem> items;
  final bool isRecurring;
  final DateTime? issuedAt;

  factory PatientPrescription.fromJson(Map<String, dynamic> d) => PatientPrescription(
    id: '${d['id']}',
    medicationDetails: '${d['medicationDetails'] ?? ''}',
    items: [
      for (final i in (d['items'] as List? ?? const []))
        OrderItem.fromJson(Map<String, dynamic>.from(i as Map)),
    ],
    isRecurring: d['isRecurring'] == true,
    issuedAt: _time(d['issuedAt']),
  );
}

/// One pharmacy chat message (D-69).
class PharmacyMessage {
  const PharmacyMessage({
    required this.id,
    required this.patientId,
    required this.senderRole,
    required this.senderName,
    required this.text,
    this.sentAt,
  });

  final String id;
  final String patientId;

  /// patient | pharmacist
  final String senderRole;
  final String senderName;
  final String text;
  final DateTime? sentAt;

  bool get fromPharmacy => senderRole == 'pharmacist';

  factory PharmacyMessage.fromJson(Map<String, dynamic> d) => PharmacyMessage(
    id: '${d['id']}',
    patientId: '${d['patientId'] ?? ''}',
    senderRole: '${d['senderRole'] ?? ''}',
    senderName: '${d['senderName'] ?? ''}',
    text: '${d['text'] ?? ''}',
    sentAt: _time(d['sentAt']),
  );
}

/// The latest message of each patient's pharmacy conversation (pharmacist inbox).
class PharmacyConversation {
  const PharmacyConversation({required this.last, this.patientName});
  final PharmacyMessage last;
  final String? patientName;
}

/// D-70 order tracking: status groups as the backend's ORDER_GROUPS.
const orderGroups = {
  'all': 'All',
  'awaiting_patient': 'Awaiting patient',
  'in_pharmacy': 'In pharmacy',
  'out_for_delivery': 'Out for delivery',
  'completed': 'Completed',
  'failed': 'Failed',
};

class OrdersOverview {
  const OrdersOverview({required this.orders, required this.counts});
  final List<MedicationOrder> orders;
  final Map<String, int> counts;

  int get total => counts.values.fold(0, (a, b) => a + b);
}
