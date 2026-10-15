import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/family_providers.dart';

/// D-62: while an emergency alert is open (< 1 h, not acknowledged), the patient app sends
/// its location every minute when it is open on screen. No background tracking.
class EmergencyLocationUpdater extends ConsumerStatefulWidget {
  const EmergencyLocationUpdater({
    super.key,
    required this.child,
    this.every = const Duration(minutes: 1),
  });

  final Widget child;
  final Duration every;

  @override
  ConsumerState<EmergencyLocationUpdater> createState() => _EmergencyLocationUpdaterState();
}

class _EmergencyLocationUpdaterState extends ConsumerState<EmergencyLocationUpdater>
    with WidgetsBindingObserver {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _check();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _check();
    } else if (state == AppLifecycleState.paused) {
      _timer?.cancel();
      _timer = null;
    }
  }

  Future<void> _check() async {
    try {
      final open = await ref.read(familyRepositoryProvider).openEmergencies();
      if (!mounted) return;
      if (open == 0) {
        _timer?.cancel();
        _timer = null;
        return;
      }
      await _send();
      _timer ??= Timer.periodic(widget.every, (_) => _check());
    } catch (_) {
      // Offline or signed out: try again on the next resume.
    }
  }

  Future<void> _send() async {
    if (!await ref.read(locationSourceProvider).granted()) return;
    final loc = await ref.read(locationSourceProvider).current();
    if (loc != null) await ref.read(familyRepositoryProvider).updateLocation(loc);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
