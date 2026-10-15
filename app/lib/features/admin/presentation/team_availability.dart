import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/enums.dart';
import '../data/admin_repository.dart';
import '../state/admin_providers.dart';

/// Caseload bands on Patient Assignments (Fig 4.3.14.2; D-59).
enum Capacity {
  available('Available'),
  near('Near capacity'),
  full('Full');

  const Capacity(this.label);
  final String label;

  static Capacity of(int caseload, int max) => caseload >= max
      ? full
      : caseload >= max * 0.8
      ? near
      : available;

  Color get color => switch (this) {
    available => Colors.green.shade700,
    near => Colors.orange.shade800,
    full => Colors.red.shade700,
  };
}

extension DoctorCapacity on AdminUser {
  Capacity get capacity => Capacity.of(caseload ?? 0, maxPatients ?? 30);
}

/// Active doctors by uid, with caseload (D-59).
final doctorCaseloadsProvider = Provider.autoDispose<AsyncValue<Map<String, AdminUser>>>(
  (ref) => ref
      .watch(adminUsersProvider((UserRole.doctor, '')))
      .whenData(
        (l) => {
          for (final d in l)
            if (d.isActive) d.uid: d,
        },
      ),
);

/// "Clinical Team Availability" panel.
class TeamAvailability extends ConsumerWidget {
  const TeamAvailability({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final doctors = ref.watch(doctorCaseloadsProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Clinical team availability', style: theme.textTheme.titleLarge),
        const SizedBox(height: 4),
        Wrap(
          spacing: 16,
          children: [
            for (final c in Capacity.values)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.circle, size: 10, color: c.color),
                  const SizedBox(width: 4),
                  Text(c.label),
                ],
              ),
          ],
        ),
        const SizedBox(height: 8),
        doctors.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, _) => const Text('Could not load caseloads.'),
          data: (map) {
            final list = map.values.toList()
              ..sort((a, b) => (a.caseload ?? 0).compareTo(b.caseload ?? 0));
            if (list.isEmpty) return const Text('No active doctors yet.');
            return Column(
              children: [
                for (final d in list)
                  Card(
                    key: Key('caseload-${d.uid}'),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(d.name, style: theme.textTheme.titleMedium),
                                    Text(d.specialty ?? 'Doctor'),
                                  ],
                                ),
                              ),
                              Chip(
                                label: Text(d.capacity.label),
                                labelStyle: TextStyle(color: d.capacity.color),
                                side: BorderSide(color: d.capacity.color),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              const Expanded(child: Text('Current caseload')),
                              Text(
                                '${d.caseload ?? 0} / ${d.maxPatients ?? 30} patients',
                                style: TextStyle(color: d.capacity.color),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          LinearProgressIndicator(
                            value: ((d.caseload ?? 0) / (d.maxPatients ?? 30)).clamp(0.0, 1.0),
                            color: d.capacity.color,
                            minHeight: 6,
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}
