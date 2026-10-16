import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../appointments/domain/appointment_text.dart' show dateLabel;
import '../../medications/domain/med_schedule.dart' show describeSchedule;
import '../data/order_models.dart';
import '../state/orders_providers.dart';
import 'order_widgets.dart';

/// D-69: a pharmacy patient's dispensing details: profile, allergies and conditions,
/// medicines, prescriptions and orders. No readings, risk, notes or record files.
class PharmacyPatientPage extends ConsumerWidget {
  const PharmacyPatientPage({super.key, required this.patientId});
  final String patientId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detail = ref.watch(pharmacyPatientProvider(patientId));
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Row(
          children: [
            TextButton.icon(
              key: const Key('back-to-patients'),
              onPressed: () => context.go('/pharmacy/patients'),
              icon: const Icon(Icons.arrow_back),
              label: const Text('Patients'),
            ),
            const Spacer(),
            FilledButton.tonalIcon(
              key: const Key('message-patient'),
              onPressed: () => context.go('/pharmacy/messages/$patientId'),
              icon: const Icon(Icons.chat_outlined),
              label: const Text('Message patient'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        detail.when(
          loading: () => const LinearProgressIndicator(),
          error: (_, _) => const Text('This patient could not be loaded.'),
          data: (p) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(p.name, style: theme.textTheme.headlineSmall),
              Text(
                [if (p.age != null) '${p.age} years', ?p.gender, ?p.phone, ?p.email].join(' · '),
              ),
              if (p.address != null) Text('Address: ${p.address}'),
              const SizedBox(height: 12),
              Card(
                key: const Key('patient-allergies'),
                color: p.allergies.isEmpty ? null : theme.colorScheme.errorContainer,
                child: ListTile(
                  leading: const Icon(Icons.warning_amber_outlined),
                  title: Text(
                    p.allergies.isEmpty ? 'No known allergies' : 'Allergies: ${p.allergies}',
                  ),
                  subtitle: Text(
                    p.conditions.isEmpty
                        ? 'No conditions recorded'
                        : 'Conditions: ${p.conditions.map((c) => c.replaceAll('_', ' ')).join(', ')}',
                  ),
                ),
              ),
              _Section(
                title: 'Current medicines',
                children: [
                  if (p.medications.isEmpty) const Text('None recorded.'),
                  for (final m in p.medications)
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(
                        m.fromDoctor ? Icons.medical_services_outlined : Icons.person_outline,
                      ),
                      title: Text('${m.name} · ${m.dosage}'),
                      subtitle: Text(
                        [
                          describeSchedule(m.schedule),
                          if (m.quantityOnHand != null)
                            '${m.quantityOnHand!.toStringAsFixed(0)} left',
                          m.fromDoctor ? 'from ${m.prescribedBy ?? 'doctor'}' : 'self-added',
                        ].join(' · '),
                      ),
                    ),
                ],
              ),
              _Section(
                title: 'Prescriptions',
                children: [
                  if (p.prescriptions.isEmpty) const Text('None.'),
                  for (final r in p.prescriptions)
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        r.items.isEmpty
                            ? r.medicationDetails
                            : r.items
                                  .map(
                                    (i) =>
                                        '${i.label} ${i.dose}, ${frequencyLabel(i.frequency).toLowerCase()} ×${i.quantity}',
                                  )
                                  .join('\n'),
                      ),
                      subtitle: Text(
                        [
                          if (r.issuedAt != null) 'Issued ${dateLabel(r.issuedAt!)}',
                          if (r.isRecurring) 'repeats monthly',
                        ].join(' · '),
                      ),
                    ),
                ],
              ),
              _Section(
                title: 'Orders and payments',
                children: [
                  if (p.orders.isEmpty) const Text('None.'),
                  for (final o in p.orders)
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text('${o.ref} · ${cycleLabel(o.cycleDate)}'),
                      subtitle: Text(
                        [
                          o.status.label,
                          'payment ${o.paymentStatus}',
                          if (o.total != null) rm(o.total!),
                          if (o.method == homeDelivery) 'delivery',
                          if (o.method == selfCollection) 'collection',
                        ].join(' · '),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.children});
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          ...children,
        ],
      ),
    ),
  );
}
