import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../shared/models/health_models.dart';
import '../../../shared/services/api/api_client.dart';
import '../../appointments/domain/appointment_text.dart' show dateLabel, timeLabel;
import '../../dashboard/state/dashboard_providers.dart';
import '../../symptom_checker/state/symptom_providers.dart' show dialerProvider;
import '../data/family_repository.dart';
import '../state/family_providers.dart';

final _readingsProvider = StreamProvider.autoDispose.family<List<VitalReading>, String>(
  (ref, id) => ref.watch(dashboardRepositoryProvider).recentReadings(id, limit: 10),
);

String agoLabel(DateTime t, DateTime now) {
  final m = now.difference(t).inMinutes;
  if (m < 1) return 'just now';
  if (m < 60) return '$m minute${m == 1 ? '' : 's'} ago';
  final h = m ~/ 60;
  return h < 24 ? '$h hour${h == 1 ? '' : 's'} ago' : '${dateLabel(t)}, ${timeLabel(t)}';
}

/// Emergency Alert (Fig 4.3.16.3; UC15.2, UC15.3): what happened, where (live map while
/// the alert is open), and one-tap call / navigate / acknowledge.
class AlertPage extends ConsumerStatefulWidget {
  const AlertPage({super.key, required this.alertId});

  final String alertId;

  @override
  ConsumerState<AlertPage> createState() => _AlertPageState();
}

class _AlertPageState extends ConsumerState<AlertPage> {
  bool _busy = false;

  Future<void> _acknowledge(EmergencyAlert a) async {
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(familyRepositoryProvider).acknowledge(a.id);
      messenger.showSnackBar(const SnackBar(content: Text('Acknowledged. They have been told.')));
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      messenger.showSnackBar(const SnackBar(content: Text('Could not acknowledge. Try again.')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final alerts = ref.watch(myEmergencyAlertsProvider);
    final now = ref.watch(nowProvider)();
    return Scaffold(
      appBar: AppBar(
        leading: BackButton(
          onPressed: () => context.canPop() ? context.pop() : context.go('/family/home'),
        ),
        title: const Text('Family Dashboard'),
      ),
      body: alerts.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => const Center(child: Text('Could not load the alert.')),
        data: (list) {
          final a = list.where((x) => x.id == widget.alertId).firstOrNull;
          if (a == null) return const Center(child: Text('This alert is no longer available.'));
          return _body(context, a, now);
        },
      ),
    );
  }

  Widget _body(BuildContext context, EmergencyAlert a, DateTime now) {
    final theme = Theme.of(context);
    final red = Colors.red.shade700;
    final person = ref.watch(linkedPersonProvider(a.patientId)).value;
    final name = person?.name ?? 'Your family member';
    final readings = ref.watch(_readingsProvider(a.patientId)).value ?? const <VitalReading>[];
    final reading = readings
        .where((r) => !r.timestamp.isAfter(a.sentAt.add(const Duration(minutes: 1))))
        .firstOrNull;
    final showReading = reading != null && a.sentAt.difference(reading.timestamp).inMinutes < 30;
    final mapBuilder = ref.watch(mapBuilderProvider);
    final dial = ref.read(dialerProvider);
    final open = ref.read(openUrlProvider);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Center(
          child: Chip(
            key: const Key('alert-badge'),
            backgroundColor: red,
            avatar: const Icon(Icons.warning_amber, color: Colors.white),
            label: const Text(
              'Emergency Alert',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
            ),
          ),
        ),
        Center(child: Text('$name · ${a.title.toLowerCase()}')),
        const SizedBox(height: 12),
        Card(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: red, width: 2),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(a.title, style: theme.textTheme.titleLarge),
                Text('Detected ${agoLabel(a.sentAt, now)}', key: const Key('alert-when')),
                if (showReading) ...[
                  const SizedBox(height: 8),
                  Text(
                    '${reading.systolic}/${reading.diastolic} mmHg',
                    key: const Key('alert-reading'),
                    style: theme.textTheme.displaySmall?.copyWith(color: red),
                  ),
                ],
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(12),
                  color: red.withValues(alpha: 0.08),
                  child: Text(switch (a.trigger) {
                    'sos' =>
                      '$name asked for help. Contact them now; call 999 if they '
                          'are unwell or do not answer.',
                    'triage' =>
                      '$name reported symptoms that need emergency care. Contact '
                          'them now; call 999 if they do not answer.',
                    _ =>
                      'Severe risk zone. Contact them now; call 999 if they are unwell or '
                          'do not answer.',
                  }),
                ),
                const SizedBox(height: 12),
                if (a.hasLocation) ...[
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: SizedBox(
                      key: const Key('alert-map'),
                      height: 220,
                      child: mapBuilder(a.lat!, a.lng!, name),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    a.savedLocation
                        ? 'Saved home location (their phone shared no live location)'
                        : 'Phone location · updated ${agoLabel(a.locationTime, now)}',
                    key: const Key('alert-location-time'),
                    style: theme.textTheme.bodySmall,
                  ),
                ] else
                  const ListTile(
                    key: Key('alert-no-location'),
                    leading: Icon(Icons.location_off),
                    title: Text('Location not shared'),
                    subtitle: Text('Their phone did not provide a location for this alert.'),
                  ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  key: const Key('alert-call-patient'),
                  style: FilledButton.styleFrom(backgroundColor: red),
                  onPressed: a.patientPhone == null ? null : () => dial(a.patientPhone!),
                  icon: const Icon(Icons.call),
                  label: Text(
                    a.patientPhone == null ? 'No phone number on file' : 'Call $name now',
                  ),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  key: const Key('alert-call-999'),
                  onPressed: () => dial('999'),
                  icon: const Icon(Icons.local_hospital),
                  label: const Text('Call 999'),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  alignment: WrapAlignment.center,
                  children: [
                    SizedBox(
                      width: 150,
                      child: OutlinedButton.icon(
                        key: const Key('alert-navigate'),
                        onPressed: a.hasLocation ? () => open(directionsUrl(a.lat!, a.lng!)) : null,
                        icon: const Icon(Icons.directions_car),
                        label: const Text('Navigate'),
                      ),
                    ),
                    SizedBox(
                      width: 170,
                      child: OutlinedButton.icon(
                        key: const Key('alert-ack'),
                        onPressed: a.isAcknowledged || _busy ? null : () => _acknowledge(a),
                        icon: const Icon(Icons.check),
                        label: Text(a.isAcknowledged ? 'Acknowledged' : 'Acknowledge'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
