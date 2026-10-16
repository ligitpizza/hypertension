import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/portal_providers.dart';

/// D-72 (M8): how the patient gets their medicines, from their latest order. Shown on the
/// doctor's patient page (Medications tab) and on the Prescription page.
class DeliveryPreferenceCard extends ConsumerWidget {
  const DeliveryPreferenceCard({super.key, required this.patientId});
  final String patientId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final value = ref.watch(deliveryPreferenceProvider(patientId));
    return Card(
      key: const Key('delivery-preference'),
      child: value.when(
        loading: () => const ListTile(
          dense: true,
          leading: Icon(Icons.local_shipping_outlined),
          title: Text('Medication delivery'),
          subtitle: LinearProgressIndicator(),
        ),
        error: (_, _) => ListTile(
          dense: true,
          leading: const Icon(Icons.cloud_off),
          title: const Text('Medication delivery'),
          subtitle: const Text('Could not load the delivery preference.'),
          trailing: TextButton(
            onPressed: () => ref.invalidate(deliveryPreferenceProvider(patientId)),
            child: const Text('Retry'),
          ),
        ),
        data: (pref) {
          final method = switch (pref['method']) {
            'home_delivery' => 'Home delivery',
            'self_collection' => 'Self-collection at the pharmacy',
            _ => 'Not chosen yet',
          };
          final status = pref['latestStatus'] as String?;
          return ListTile(
            dense: true,
            leading: Icon(
              pref['method'] == 'home_delivery'
                  ? Icons.local_shipping_outlined
                  : Icons.storefront_outlined,
            ),
            title: Text('Medication delivery: $method'),
            subtitle: Text(
              '${pref['orders'] ?? 0} order(s)'
              '${status == null ? '' : ' · latest ${status.replaceAll('_', ' ')}'}',
            ),
          );
        },
      ),
    );
  }
}
