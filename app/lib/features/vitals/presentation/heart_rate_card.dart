import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/bp_classifier.dart';
import '../data/ppg_capture.dart';
import '../domain/ppg.dart';
import '../state/vitals_providers.dart';

/// "Measure Heart Rate" card (Fig 4.3.3.2, UC3.3). Shows a live camera preview so the
/// patient can place the fingertip, then measures. Reports the measured or manually
/// entered heart rate through [onChanged]; null means none.
class HeartRateCard extends ConsumerStatefulWidget {
  const HeartRateCard({super.key, required this.onChanged, this.allowSkip = true});

  final ValueChanged<int?> onChanged;

  /// False in the symptom checker, where heart rate is compulsory (D-38): no Skip button;
  /// the camera or a typed pulse must provide it.
  final bool allowSkip;

  @override
  ConsumerState<HeartRateCard> createState() => _HeartRateCardState();
}

enum _Phase { idle, opening, positioning, measuring, done, failed, unavailable, manual }

class _HeartRateCardState extends ConsumerState<HeartRateCard> {
  _Phase _phase = _Phase.idle;
  double _progress = 0;
  List<double> _trace = const [];
  int? _bpm;
  String _message = '';
  final _manual = TextEditingController();
  // Kept so dispose() can stop the camera without touching ref.
  late final PpgCapture _capture;

  @override
  void initState() {
    super.initState();
    _capture = ref.read(ppgCaptureProvider);
  }

  @override
  void dispose() {
    _manual.dispose();
    _capture.cancel();
    super.dispose();
  }

  /// Step 1: camera + torch + live preview, so the patient can find the lens.
  Future<void> _openCamera() async {
    setState(() => _phase = _Phase.opening);
    try {
      await _capture.open();
      if (mounted) setState(() => _phase = _Phase.positioning);
    } on PpgUnavailableException catch (e) {
      if (!mounted) return;
      setState(() {
        _phase = _Phase.unavailable;
        _message = switch (e.reason) {
          PpgUnavailable.permissionDenied =>
            'Camera access was denied. Allow it in your phone settings, or enter your heart rate.',
          _ => 'The camera is not available on this device. You can enter your heart rate instead.',
        };
      });
    }
  }

  /// Step 2: record and estimate.
  Future<void> _measure() async {
    setState(() {
      _phase = _Phase.measuring;
      _progress = 0;
      _trace = const [];
    });
    final result = await _capture.measure(
      onProgress: (p, trace) {
        if (mounted) {
          setState(() {
            _progress = p;
            _trace = trace;
          });
        }
      },
    );
    await _capture.cancel(); // torch off as soon as the frames are in
    if (!mounted) return;
    if (result.ok) {
      setState(() {
        _phase = _Phase.done;
        _bpm = result.bpm;
      });
      widget.onChanged(result.bpm);
    } else {
      // UC3.3 E1: poor signal -> reposition and retry, or skip.
      setState(() {
        _phase = _Phase.failed;
        _message = switch (result.failure) {
          PpgFailure.tooShort => 'The measurement stopped too early.',
          _ => 'We could not get a clear pulse signal.',
        };
      });
    }
  }

  Future<void> _stop() async {
    await _capture.cancel();
    if (mounted) setState(() => _phase = _Phase.idle);
  }

  void _skip() {
    setState(() {
      _phase = _Phase.idle;
      _bpm = null;
    });
    widget.onChanged(null);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      key: const Key('heart-rate-card'),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.tertiaryContainer.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          CircleAvatar(
            radius: 28,
            backgroundColor: scheme.surface,
            child: Icon(Icons.monitor_heart_outlined, color: scheme.tertiary),
          ),
          const SizedBox(height: 8),
          Text('Measure Heart Rate', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          const Text(
            "Place your fingertip completely over your phone's rear camera lens. Keep still.",
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          _body(context),
        ],
      ),
    );
  }

  Widget _preview(double size) {
    return ClipRRect(
      key: const Key('ppg-preview'),
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(
        width: size,
        height: size,
        child: FittedBox(
          fit: BoxFit.cover,
          clipBehavior: Clip.hardEdge,
          child: SizedBox(width: size, height: size, child: _capture.preview()),
        ),
      ),
    );
  }

  Widget _fingerHint() {
    return ValueListenableBuilder<bool>(
      valueListenable: _capture.fingerDetected,
      builder: (context, covered, _) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            covered ? Icons.check_circle : Icons.touch_app_outlined,
            color: covered ? Colors.green : null,
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              covered ? 'Finger detected' : 'Cover the lens and the light with your fingertip',
              key: const Key('ppg-finger-hint'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _body(BuildContext context) {
    switch (_phase) {
      case _Phase.idle:
        return Column(
          children: [
            FilledButton.tonalIcon(
              key: const Key('ppg-start'),
              onPressed: _openCamera,
              icon: const Icon(Icons.camera_outlined),
              label: const Text('Tap to Start Camera'),
            ),
            TextButton(
              key: const Key('ppg-manual'),
              onPressed: () => setState(() => _phase = _Phase.manual),
              child: const Text('Enter heart rate manually'),
            ),
          ],
        );
      case _Phase.opening:
        return const Padding(padding: EdgeInsets.all(16), child: CircularProgressIndicator());
      case _Phase.positioning:
        return Column(
          key: const Key('ppg-positioning'),
          children: [
            _preview(160),
            const SizedBox(height: 8),
            const Text(
              'This is your rear camera. Cover the lens and the light next to it until the '
              'picture turns evenly red, then tap Start measuring.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            _fingerHint(),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              alignment: WrapAlignment.center,
              children: [
                FilledButton(
                  key: const Key('ppg-measure'),
                  onPressed: _measure,
                  child: const Text('Start measuring'),
                ),
                TextButton(onPressed: _stop, child: const Text('Cancel')),
              ],
            ),
          ],
        );
      case _Phase.measuring:
        return Column(
          key: const Key('ppg-measuring'),
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _preview(90),
                const SizedBox(width: 16),
                SizedBox(
                  width: 72,
                  height: 72,
                  child: CircularProgressIndicator(value: _progress, strokeWidth: 6),
                ),
              ],
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 48,
              width: double.infinity,
              child: CustomPaint(
                painter: _TracePainter(_trace, Theme.of(context).colorScheme.tertiary),
              ),
            ),
            _fingerHint(),
            const Text('Measuring… keep your finger still.'),
            TextButton(onPressed: _stop, child: const Text('Cancel')),
          ],
        );
      case _Phase.done:
        return Column(
          children: [
            Text(
              '$_bpm BPM',
              key: const Key('ppg-result'),
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            // Ch1 limitation: camera PPG is supplementary and less accurate than a device.
            const Text(
              'Estimate from your phone camera, not a medical measurement.',
              textAlign: TextAlign.center,
            ),
            TextButton(onPressed: _openCamera, child: const Text('Measure again')),
          ],
        );
      case _Phase.failed:
      case _Phase.unavailable:
        return Column(
          key: Key(_phase == _Phase.failed ? 'ppg-failed' : 'ppg-unavailable'),
          children: [
            Text(_message, textAlign: TextAlign.center),
            if (_phase == _Phase.failed)
              const Text(
                'Cover the lens fully, rest your hand, and try again.',
                textAlign: TextAlign.center,
              ),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 8,
              children: [
                if (_phase == _Phase.failed)
                  FilledButton(
                    key: const Key('ppg-retry'),
                    onPressed: _openCamera,
                    child: const Text('Retry'),
                  ),
                if (widget.allowSkip)
                  OutlinedButton(
                    key: const Key('ppg-skip'),
                    onPressed: _skip,
                    child: const Text('Skip'),
                  ),
                TextButton(
                  onPressed: () => setState(() => _phase = _Phase.manual),
                  child: const Text('Enter manually'),
                ),
              ],
            ),
          ],
        );
      case _Phase.manual:
        return Row(
          children: [
            Expanded(
              child: TextField(
                key: const Key('hr-manual-input'),
                controller: _manual,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(labelText: 'Heart rate', suffixText: 'bpm'),
                onChanged: (v) {
                  final n = int.tryParse(v);
                  final ok =
                      n != null && n >= BpClassifier.heartRateMin && n <= BpClassifier.heartRateMax;
                  widget.onChanged(ok ? n : null);
                },
              ),
            ),
            TextButton(onPressed: _skip, child: const Text('Clear')),
          ],
        );
    }
  }
}

class _TracePainter extends CustomPainter {
  _TracePainter(this.values, this.color);

  final List<double> values;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.length < 2) return;
    final lo = values.reduce((a, b) => a < b ? a : b);
    final hi = values.reduce((a, b) => a > b ? a : b);
    final range = (hi - lo).abs() < 1e-6 ? 1.0 : hi - lo;
    final path = Path();
    for (var i = 0; i < values.length; i++) {
      final x = size.width * i / (values.length - 1);
      final y = size.height * (1 - (values[i] - lo) / range);
      i == 0 ? path.moveTo(x, y) : path.lineTo(x, y);
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(_TracePainter old) => old.values != values;
}
