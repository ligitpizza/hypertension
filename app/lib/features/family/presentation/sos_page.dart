import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';

import '../../../shared/models/health_models.dart';
import '../../appointments/domain/appointment_text.dart' show dateLabel, timeLabel;
import '../../dashboard/state/dashboard_providers.dart';
import '../../symptom_checker/state/symptom_providers.dart' show dialerProvider;
import '../data/location_source.dart';
import '../state/family_providers.dart';

/// Shares text (share sheet); tests record it.
final shareTextProvider = Provider<Future<void> Function(String text)>(
  (ref) => (text) async {
    await SharePlus.instance.share(ShareParams(text: text));
  },
);

String vitalsSummary(List<VitalReading> readings) {
  if (readings.isEmpty) return 'Harvey: no recent blood pressure readings.';
  final lines = [
    for (final r in readings.take(5))
      '${dateLabel(r.timestamp)} ${timeLabel(r.timestamp)}: ${r.systolic}/${r.diastolic} mmHg'
          '${r.heartRate == null ? '' : ', HR ${r.heartRate} (camera estimate)'}',
  ];
  return 'Harvey recent vitals:\n${lines.join('\n')}';
}

/// Emergency SOS (Fig 4.3.9.1; FR-14.2, D-62): call 999, nearest hospitals, share vitals,
/// alert family with the phone's location.
class SosPage extends ConsumerStatefulWidget {
  const SosPage({super.key});

  @override
  ConsumerState<SosPage> createState() => _SosPageState();
}

class _SosPageState extends ConsumerState<SosPage> {
  bool _notifyFamily = true;
  bool _busy = false;
  Map<String, double>? _here;
  LocationAccess? _problem;
  bool _locating = true;

  @override
  void initState() {
    super.initState();
    _locate();
  }

  /// Asking here is expected: the patient opened SOS on purpose.
  Future<void> _locate() async {
    setState(() => _locating = true);
    final source = ref.read(locationSourceProvider);
    final access = await source.request();
    final here = access == LocationAccess.granted ? await source.current() : null;
    if (!mounted) return;
    setState(() {
      _locating = false;
      _problem = access == LocationAccess.granted ? null : access;
      _here = here;
    });
  }

  Future<void> _alertFamily({bool thenCall = false}) async {
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    final dial = ref.read(dialerProvider);
    try {
      final n = await ref
          .read(familyRepositoryProvider)
          .sos(
            location: _here ?? await ref.read(locationSourceProvider).current(),
            notifyFamily: _notifyFamily,
          );
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            !_notifyFamily
                ? 'Your doctor has been notified.'
                : n == 0
                ? 'No family member is linked. Your doctor has been notified.'
                : 'Family alerted ($n) and your doctor notified.',
          ),
        ),
      );
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Could not send the alert. Call 999 if you need help.')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    if (thenCall) await dial('999');
  }

  @override
  Widget build(BuildContext context) {
    final red = Colors.red.shade700;
    final map = ref.watch(mapBuilderProvider);
    final readings = ref.watch(recentReadingsProvider).value ?? const <VitalReading>[];
    return Scaffold(
      appBar: AppBar(
        leading: BackButton(
          onPressed: () => context.canPop() ? context.pop() : context.go('/dashboard'),
        ),
        title: const Text('Emergency'),
      ),
      body: ListView(
        children: [
          Container(
            color: red,
            padding: const EdgeInsets.all(20),
            child: const Column(
              children: [
                Icon(Icons.warning_rounded, color: Colors.white, size: 40),
                SizedBox(height: 8),
                Text(
                  'Emergency SOS',
                  style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold),
                ),
                SizedBox(height: 4),
                Text(
                  'If you are experiencing a medical emergency, call 999 immediately.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white),
                ),
              ],
            ),
          ),
          SizedBox(
            key: const Key('sos-map'),
            height: 200,
            child: _here == null
                ? _NoLocation(
                    locating: _locating,
                    problem: _problem,
                    onRetry: () async {
                      final p = _problem;
                      if (p == LocationAccess.serviceOff || p == LocationAccess.deniedForever) {
                        await ref.read(locationSourceProvider).openSettings(p!);
                      }
                      await _locate();
                    },
                  )
                : map(_here!['lat']!, _here!['lng']!, 'You are here'),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Card(
                  child: ListTile(
                    key: const Key('sos-hospitals'),
                    leading: const Icon(Icons.local_hospital_outlined),
                    title: const Text('Nearest hospitals'),
                    subtitle: const Text('Opens Google Maps'),
                    trailing: const Icon(Icons.open_in_new),
                    onTap: () =>
                        ref.read(openUrlProvider)(hospitalsNearUrl(_here?['lat'], _here?['lng'])),
                  ),
                ),
                const SizedBox(height: 8),
                FilledButton.icon(
                  key: const Key('sos-call-999'),
                  style: FilledButton.styleFrom(
                    backgroundColor: red,
                    minimumSize: const Size.fromHeight(56),
                  ),
                  onPressed: _busy ? null : () => _alertFamily(thenCall: true),
                  icon: const Icon(Icons.call),
                  label: const Text('Call 999 Now', style: TextStyle(fontSize: 18)),
                ),
                const SizedBox(height: 8),
                FilledButton.tonalIcon(
                  key: const Key('sos-share'),
                  onPressed: () => ref.read(shareTextProvider)(vitalsSummary(readings)),
                  icon: const Icon(Icons.monitor_heart_outlined),
                  label: const Text('Share live vitals with ER'),
                ),
                const SizedBox(height: 8),
                Card(
                  child: SwitchListTile(
                    key: const Key('sos-notify'),
                    secondary: const Icon(Icons.contact_emergency_outlined),
                    title: const Text('Notify emergency contacts'),
                    subtitle: const Text('Alerts linked family with your location'),
                    value: _notifyFamily,
                    onChanged: (v) => setState(() => _notifyFamily = v),
                  ),
                ),
                OutlinedButton.icon(
                  key: const Key('sos-alert-only'),
                  onPressed: _busy ? null : _alertFamily,
                  icon: const Icon(Icons.campaign_outlined),
                  label: Text(
                    _notifyFamily ? 'Alert family and doctor now' : 'Alert my doctor now',
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _NoLocation extends StatelessWidget {
  const _NoLocation({required this.locating, required this.problem, required this.onRetry});

  final bool locating;
  final LocationAccess? problem;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    if (locating) return const Center(child: Text('Finding your location…'));
    final (advice, action) = problem == null
        ? ('Your location could not be found. Your family will be alerted without it.', null)
        : locationAdvice(problem!);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.location_off),
            const SizedBox(height: 4),
            Text(advice, key: const Key('sos-location-advice'), textAlign: TextAlign.center),
            TextButton(
              key: const Key('sos-location-retry'),
              onPressed: onRetry,
              child: Text(action ?? 'Try again'),
            ),
          ],
        ),
      ),
    );
  }
}
