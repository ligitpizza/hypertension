import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';

import '../domain/ppg.dart';

/// Why a camera measurement could not run at all (as opposed to a noisy signal).
enum PpgUnavailable { noCamera, permissionDenied, notSupported }

class PpgUnavailableException implements Exception {
  const PpgUnavailableException(this.reason);
  final PpgUnavailable reason;
}

/// Live progress while measuring: 0..1 and the recent signal for the trace.
typedef PpgProgress = void Function(double progress, List<double> recentSignal);

/// Camera PPG capture (FR-3.2, UC3.3). Behind an interface so screens can be
/// tested without a camera.
abstract interface class PpgCapture {
  Future<PpgResult> measure({required PpgProgress onProgress, Duration duration});

  Future<void> cancel();
}

/// Rear camera + torch, one mean green value per frame, processed in an isolate.
class CameraPpgCapture implements PpgCapture {
  static const defaultDuration = Duration(seconds: 15);

  CameraController? _controller;
  Completer<void>? _done;

  @override
  Future<PpgResult> measure({
    required PpgProgress onProgress,
    Duration duration = defaultDuration,
  }) async {
    if (kIsWeb) throw const PpgUnavailableException(PpgUnavailable.notSupported);
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
    } on CameraException catch (e) {
      await _release();
      throw PpgUnavailableException(
        e.code.contains('Denied') ? PpgUnavailable.permissionDenied : PpgUnavailable.noCamera,
      );
    }

    final times = <double>[];
    final values = <double>[];
    final clock = Stopwatch()..start();
    final done = Completer<void>();
    _done = done;
    try {
      await controller.setFlashMode(FlashMode.torch);
      await controller.startImageStream((image) {
        if (done.isCompleted) return;
        final g = greenMean(image);
        if (g == null) return;
        times.add(clock.elapsedMicroseconds / 1e6);
        values.add(g);
        final p = (clock.elapsed.inMilliseconds / duration.inMilliseconds).clamp(0.0, 1.0);
        final start = values.length > 90 ? values.length - 90 : 0;
        onProgress(p, values.sublist(start));
        if (clock.elapsed >= duration) done.complete();
      });
      await done.future;
    } finally {
      await _release();
    }
    if (values.length < 2) return const PpgResult.failed(PpgFailure.tooShort);
    return compute(estimateHeartRate, PpgInput(times, values));
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
  /// sampling every 4th pixel to keep the per-frame cost tiny.
  static double? greenMean(CameraImage image) {
    if (image.planes.length < 3) return null;
    final y = image.planes[0];
    final u = image.planes[1];
    final v = image.planes[2];
    final uvStride = u.bytesPerPixel ?? 1;
    final w = image.width;
    final h = image.height;
    var sum = 0.0;
    var n = 0;
    for (var row = h ~/ 4; row < 3 * h ~/ 4; row += 4) {
      for (var col = w ~/ 4; col < 3 * w ~/ 4; col += 4) {
        final yv = y.bytes[row * y.bytesPerRow + col];
        final uvIndex = (row ~/ 2) * u.bytesPerRow + (col ~/ 2) * uvStride;
        if (uvIndex >= u.bytes.length || uvIndex >= v.bytes.length) continue;
        final uu = u.bytes[uvIndex] - 128;
        final vv = v.bytes[uvIndex] - 128;
        sum += yv - 0.344 * uu - 0.714 * vv; // YUV -> G
        n++;
      }
    }
    return n == 0 ? null : sum / n;
  }
}
