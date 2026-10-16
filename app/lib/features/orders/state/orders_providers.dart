import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/providers/api_providers.dart';
import '../data/order_models.dart';
import '../data/orders_repository.dart';
import '../data/payment_sheet.dart';

Duration? _noRetry(int _, Object _) => null;

final ordersRepositoryProvider = Provider<OrdersRepository>(
  (ref) => ApiOrdersRepository(ref.watch(apiClientProvider)),
);

final paymentSheetProvider = Provider<PaymentSheetLauncher>((ref) => StripePaymentSheet());

/// The patient's monthly orders, newest cycle first (UC13.2).
final myOrdersProvider = FutureProvider.autoDispose<List<MedicationOrder>>(
  (ref) => ref.watch(ordersRepositoryProvider).myOrders(),
  retry: _noRetry,
);

/// One order with its courier events (Fig 4.3.10.3).
final orderProvider = FutureProvider.autoDispose.family<MedicationOrder, String>(
  (ref, id) => ref.watch(ordersRepositoryProvider).order(id),
  retry: _noRetry,
);

/// Pharmacist queue (Fig 4.3.13.1).
final pharmacyQueueProvider = FutureProvider.autoDispose<PharmacyQueue>(
  (ref) => ref.watch(ordersRepositoryProvider).queue(),
  retry: _noRetry,
);

final stockProvider = FutureProvider.autoDispose<List<StockItem>>(
  (ref) => ref.watch(ordersRepositoryProvider).stock(),
  retry: _noRetry,
);

final pharmacyLookupProvider = FutureProvider.autoDispose.family<List<PharmacyPatient>, String>(
  (ref, q) => ref.watch(ordersRepositoryProvider).lookup(q),
  retry: _noRetry,
);

/// D-69: the medication catalogue (doctor picker, pharmacy prices).
final catalogProvider = FutureProvider.autoDispose<List<CatalogItem>>(
  (ref) => ref.watch(ordersRepositoryProvider).catalog(),
  retry: _noRetry,
);

/// D-69: a pharmacy patient's dispensing details.
final pharmacyPatientProvider = FutureProvider.autoDispose.family<PharmacyPatientDetail, String>(
  (ref, uid) => ref.watch(ordersRepositoryProvider).pharmacyPatient(uid),
  retry: _noRetry,
);

/// D-69: the patient's pharmacy conversation.
final myPharmacyChatProvider = FutureProvider.autoDispose<List<PharmacyMessage>>(
  (ref) => ref.watch(ordersRepositoryProvider).myPharmacyChat(),
  retry: _noRetry,
);

/// D-69: the pharmacist's inbox.
final pharmacyConversationsProvider = FutureProvider.autoDispose<List<PharmacyConversation>>(
  (ref) => ref.watch(ordersRepositoryProvider).pharmacyConversations(),
  retry: _noRetry,
);

final pharmacyThreadProvider = FutureProvider.autoDispose
    .family<({String patientName, List<PharmacyMessage> messages}), String>(
      (ref, uid) => ref.watch(ordersRepositoryProvider).pharmacyThread(uid),
      retry: _noRetry,
    );

/// D-70 order tracking (pharmacist Tracking tab, admin Orders tab).
final ordersOverviewProvider = FutureProvider.autoDispose
    .family<OrdersOverview, ({String group, String query})>(
      (ref, f) =>
          ref.watch(ordersRepositoryProvider).ordersOverview(group: f.group, query: f.query),
      retry: _noRetry,
    );

/// Admin delivery oversight (Fig 4.3.14.4).
final deliveriesProvider = FutureProvider.autoDispose<DeliveryOverview>(
  (ref) => ref.watch(ordersRepositoryProvider).deliveries(),
  retry: _noRetry,
);
