import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../domain/ppg.dart';

/// Why a camera measurement could not run at all (as opposed to a noisy signal).
enum PpgUnavailable { noCamera, permissionDenied, notSupported }

class PpgUnavailableException implements Exception {
  const PpgUnavailableException(this.reason);
  final PpgUnavailable reason;
}

/// Live progress while measuring: 0..1 and the recent signal for the trace.
typedef PpgProgress = void Function(double progress, List<double> recentSignal);

/// Camera PPG capture (FR-3.2, UC3.3). Two steps so the patient can see the lens
/// before measuring: [open] starts the camera + torch and a live preview,
/// [measure] then records for the measurement window. Behind an interface so
/// screens are tested without a camera.
abstract interface class PpgCapture {
  /// Starts the rear camera, torch and live preview. Throws [PpgUnavailableException].
  Future<void> open();

  /// Live camera view; only meaningful after [open].
  Widget preview();

  /// True while the lens looks covered by a fingertip (a hint, not a gate).
  ValueListenable<bool> get fingerDetected;

  /// Records for [duration] and returns the estimate. Requires [open].
  Future<PpgResult> measure({required PpgProgress onProgress, Duration duration});

  /// Stops measuring, turns the torch off and releases the camera.
  Future<void> cancel();
}

/// Rear camera + torch, one mean green value per frame, processed in an isolate.
class CameraPpgCapture implements PpgCapture {
  static const defaultDuration = Duration(seconds: 15);

  CameraController? _controller;
  final _finger = ValueNotifier<bool>(false);

  // Active measurement, if any.
  Completer<void>? _done;
  Stopwatch? _clock;
  Duration _duration = defaultDuration;
  PpgProgress? _onProgress;
  final _times = <double>[];
  final _values = <double>[];

  @override
  ValueListenable<bool> get fingerDetected => _finger;

  @override
  Future<void> open() async {
    if (kIsWeb) throw const PpgUnavailableException(PpgUnavailable.notSupported);
    if (_controller != null) return;
    final List<CameraDescription> cameras;
    try {
      cameras = await availableCameras();
    } on CameraException {
      throw const PpgUnavailableException(PpgUnavailable.noCamera);
    }
    final back = cameras.where((c) => c.lensDirection == CameraLensDirection.back).firstOrNull;
    if (back == null) throw const PpgUnavailableException(PpgUnavailable.noCamera);

    final controller = CameraController(
      back,
      ResolutionPreset.low,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.yuv420,
    );
    _controller = controller;
    try {
      await controller.initialize();
      await controller.setFlashMode(FlashMode.torch);
      await controller.startImageStream(_onFrame);
    } on CameraException catch (e) {
      await _release();
      throw PpgUnavailableException(
        e.code.contains('Denied') ? PpgUnavailable.permissionDenied : PpgUnavailable.noCamera,
      );
    }
  }

  @override
  Widget preview() {
    final c = _controller;
    if (c == null || !c.value.isInitialized) return const SizedBox.shrink();
    return CameraPreview(c);
  }

  void _onFrame(CameraImage image) {
    final stats = frameStats(image);
    if (stats == null) return;
    _finger.value = stats.covered;

    final done = _done;
    final clock = _clock;
    if (done == null || clock == null || done.isCompleted) return;
    _times.add(clock.elapsedMicroseconds / 1e6);
    _values.add(stats.green);
    final p = (clock.elapsed.inMilliseconds / _duration.inMilliseconds).clamp(0.0, 1.0);
    final start = _values.length > 90 ? _values.length - 90 : 0;
    _onProgress?.call(p, _values.sublist(start));
    if (clock.elapsed >= _duration) done.complete();
  }

  @override
  Future<PpgResult> measure({
    required PpgProgress onProgress,
    Duration duration = defaultDuration,
  }) async {
    await open();
    _times.clear();
    _values.clear();
    _duration = duration;
    _onProgress = onProgress;
    _clock = Stopwatch()..start();
    final done = Completer<void>();
    _done = done;
    await done.future;
    _done = null;
    _clock = null;
    _onProgress = null;
    if (_values.length < 2) return const PpgResult.failed(PpgFailure.tooShort);
    return compute(estimateHeartRate, PpgInput(List.of(_times), List.of(_values)));
  }

  @override
  Future<void> cancel() async {
    final done = _done;
    if (done != null && !done.isCompleted) done.complete();
    await _release();
  }

  Future<void> _release() async {
    final c = _controller;
    _controller = null;
    _finger.value = false;
    if (c == null) return;
    try {
      if (c.value.isStreamingImages) await c.stopImageStream();
      await c.setFlashMode(FlashMode.off);
    } catch (_) {
      // Already stopped or disposed.
    }
    await c.dispose();
  }

  /// Mean green intensity over the centre of a YUV420 frame (docs/06 algorithm B),
  /// plus a "covered" hint: a fingertip lit by the torch fills the frame with a
  /// bright, strongly red image (high Cr). Samples every 4th pixel.
  static ({double green, bool covered})? frameStats(CameraImage image) {
    if (image.planes.length < 3) return null;
    final y = image.planes[0];
    final u = image.planes[1];
    final v = image.planes[2];
    final uvStride = u.bytesPerPixel ?? 1;
    final w = image.width;
    final h = image.height;
    var green = 0.0;
    var luma = 0.0;
    var red = 0.0;
    var n = 0;
    for (var row = h ~/ 4; row < 3 * h ~/ 4; row += 4) {
      for (var col = w ~/ 4; col < 3 * w ~/ 4; col += 4) {
        final yv = y.bytes[row * y.bytesPerRow + col];
        final uvIndex = (row ~/ 2) * u.bytesPerRow + (col ~/ 2) * uvStride;
        if (uvIndex >= u.bytes.length || uvIndex >= v.bytes.length) continue;
        final uu = u.bytes[uvIndex] - 128;
        final vv = v.bytes[uvIndex] - 128;
        green += yv - 0.344 * uu - 0.714 * vv; // YUV -> G
        luma += yv;
        red += vv;
        n++;
      }
    }
    if (n == 0) return null;
    return (green: green / n, covered: luma / n > 40 && red / n > 25);
  }
}
