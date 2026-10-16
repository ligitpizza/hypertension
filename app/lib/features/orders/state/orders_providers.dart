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

/// Admin delivery oversight (Fig 4.3.14.4).
final deliveriesProvider = FutureProvider.autoDispose<DeliveryOverview>(
  (ref) => ref.watch(ordersRepositoryProvider).deliveries(),
  retry: _noRetry,
);
