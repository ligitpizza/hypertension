import 'dart:math' as math;

/// Camera PPG heart-rate estimation (FR-3.2, UC3.3; docs/06 algorithm B, Yan et al. 2017).
///
/// 1. one green-channel mean per frame (fingertip over the lens, torch on)
/// 2. resample to a uniform rate and remove the slow baseline
/// 3. band-pass 0.67-3.3 Hz (40-200 bpm), zero-phase
/// 4. peak detection
/// 5. bpm = beats per minute over the span of detected beats
/// 6. reject the capture if the signal quality is too low (UC3.3 E1 / UC14.2 E1)
///
/// Pure Dart with no Flutter imports, so it runs in an isolate via `compute`
/// and is unit-tested with synthetic signals.

enum PpgFailure { tooShort, noSignal, irregular, outOfRange }

class PpgInput {
  const PpgInput(this.timesSeconds, this.greenMeans);

  /// Frame timestamps in seconds (need not be evenly spaced).
  final List<double> timesSeconds;

  /// Mean green intensity of each frame.
  final List<double> greenMeans;
}

class PpgResult {
  const PpgResult.success(this.bpm, this.quality) : failure = null;
  const PpgResult.failed(this.failure) : bpm = null, quality = 0;

  final int? bpm;

  /// 0..1, higher is a cleaner, more regular pulse.
  final double quality;
  final PpgFailure? failure;

  bool get ok => bpm != null;
}

class PpgConfig {
  const PpgConfig({
    this.sampleRate = 30,
    this.lowHz = 0.67,
    this.highHz = 3.3,
    this.settleSeconds = 1.5,
    this.minSeconds = 8,
    this.maxIntervalCv = 0.25,
  });

  final double sampleRate;
  final double lowHz;
  final double highHz;

  /// Ignore the first seconds while the finger and auto-exposure settle.
  final double settleSeconds;

  /// Minimum usable signal length after settling.
  final double minSeconds;

  /// Maximum coefficient of variation of beat intervals for a "regular" pulse.
  final double maxIntervalCv;
}

const minBpm = 40;
const maxBpm = 200;

/// Entry point used with `compute(estimateHeartRate, input)`.
PpgResult estimateHeartRate(PpgInput input, {PpgConfig config = const PpgConfig()}) {
  final t = input.timesSeconds;
  final y = input.greenMeans;
  if (t.length != y.length || t.length < 2) return const PpgResult.failed(PpgFailure.tooShort);

  final fs = config.sampleRate;
  final uniform = resample(t, y, fs);
  final skip = (config.settleSeconds * fs).round();
  if (uniform.length - skip < config.minSeconds * fs) {
    return const PpgResult.failed(PpgFailure.tooShort);
  }
  final signal = uniform.sublist(skip);

  // A covered lens with the torch on gives a small but clear pulsatile variation.
  // A flat signal means no finger, a dead camera or a frozen frame.
  if (_std(signal) < 1e-3) return const PpgResult.failed(PpgFailure.noSignal);

  final filtered = bandPass(signal, fs, config.lowHz, config.highHz);
  // Drop filter edges, where the forward-backward pass is least reliable.
  final edge = fs.round();
  if (filtered.length <= 3 * edge) return const PpgResult.failed(PpgFailure.tooShort);
  final core = filtered.sublist(edge, filtered.length - edge);

  // The dicrotic wave of each beat is also in band, so first estimate the beat
  // period (autocorrelation) and only accept peaks spaced like real beats.
  final period = dominantPeriodSamples(core, fs);
  if (period == null) return const PpgResult.failed(PpgFailure.noSignal);
  final peaks = detectPeaks(core, fs, minDistance: (0.6 * period).floor());
  if (peaks.length < 4) return const PpgResult.failed(PpgFailure.noSignal);

  final intervals = [for (var i = 1; i < peaks.length; i++) (peaks[i] - peaks[i - 1]) / fs];
  final meanInterval = intervals.reduce((a, b) => a + b) / intervals.length;
  final cv = _std(intervals) / meanInterval;
  if (cv > config.maxIntervalCv) return const PpgResult.failed(PpgFailure.irregular);

  final spanSeconds = (peaks.last - peaks.first) / fs;
  final bpm = ((peaks.length - 1) / spanSeconds * 60).round();
  if (bpm < minBpm || bpm > maxBpm) return const PpgResult.failed(PpgFailure.outOfRange);

  return PpgResult.success(bpm, (1 - cv / config.maxIntervalCv).clamp(0.0, 1.0));
}

/// Linear interpolation onto an even grid at [fs] Hz.
List<double> resample(List<double> t, List<double> y, double fs) {
  final start = t.first;
  final end = t.last;
  final n = ((end - start) * fs).floor() + 1;
  final out = List<double>.filled(n, 0);
  var j = 0;
  for (var i = 0; i < n; i++) {
    final ti = start + i / fs;
    while (j < t.length - 2 && t[j + 1] < ti) {
      j++;
    }
    final span = t[j + 1] - t[j];
    final w = span <= 0 ? 0.0 : ((ti - t[j]) / span).clamp(0.0, 1.0);
    out[i] = y[j] + (y[j + 1] - y[j]) * w;
  }
  return out;
}

/// Zero-phase band-pass: 2nd-order Butterworth high-pass then low-pass, each run
/// forward and backward (filtfilt) so peaks are not shifted in time.
List<double> bandPass(List<double> x, double fs, double lowHz, double highHz) {
  final mean = x.reduce((a, b) => a + b) / x.length;
  var s = [for (final v in x) v - mean];
  s = _filtfilt(s, _Biquad.highPass(fs, lowHz));
  s = _filtfilt(s, _Biquad.lowPass(fs, highHz));
  return s;
}

/// Beat period in samples from the autocorrelation peak within 40-200 bpm, or
/// null when there is no clear periodicity.
int? dominantPeriodSamples(List<double> x, double fs) {
  final minLag = (fs * 60 / maxBpm).floor();
  final maxLag = (fs * 60 / minBpm).ceil();
  if (x.length < 2 * maxLag) return null;
  var energy = 0.0;
  for (final v in x) {
    energy += v * v;
  }
  if (energy == 0) return null;
  final r = List<double>.filled(maxLag + 1, 0);
  for (var lag = minLag; lag <= maxLag; lag++) {
    var acc = 0.0;
    for (var i = 0; i + lag < x.length; i++) {
      acc += x[i] * x[i + lag];
    }
    r[lag] = acc / energy;
  }
  // First local maximum that is close to the global maximum: avoids picking a
  // multiple of the true period.
  final best = r.sublist(minLag).reduce(math.max);
  // Weak periodicity means noise dominates: reject rather than guess (UC3.3 E1).
  if (best < 0.45) return null;
  for (var lag = minLag + 1; lag < maxLag; lag++) {
    if (r[lag] >= r[lag - 1] && r[lag] >= r[lag + 1] && r[lag] >= 0.8 * best) return lag;
  }
  return null;
}

/// Local maxima above an adaptive threshold, at least [minDistance] samples apart
/// (default: one shortest beat).
List<int> detectPeaks(List<double> x, double fs, {int? minDistance}) {
  minDistance ??= (fs * 60 / maxBpm).floor();
  final threshold = 0.3 * _std(x);
  final peaks = <int>[];
  for (var i = 1; i < x.length - 1; i++) {
    if (x[i] <= threshold || x[i] < x[i - 1] || x[i] < x[i + 1]) continue;
    if (peaks.isNotEmpty && i - peaks.last < minDistance) {
      if (x[i] > x[peaks.last]) peaks[peaks.length - 1] = i; // keep the taller one
      continue;
    }
    peaks.add(i);
  }
  return peaks;
}

double _std(List<double> v) {
  if (v.length < 2) return 0;
  final m = v.reduce((a, b) => a + b) / v.length;
  var acc = 0.0;
  for (final e in v) {
    acc += (e - m) * (e - m);
  }
  return math.sqrt(acc / (v.length - 1));
}

List<double> _filtfilt(List<double> x, _Biquad f) {
  final forward = f.run(x);
  final backward = f.run(forward.reversed.toList());
  return backward.reversed.toList();
}

/// RBJ audio-EQ-cookbook biquad, Q = 1/sqrt(2) (Butterworth).
class _Biquad {
  _Biquad(this.b0, this.b1, this.b2, this.a1, this.a2);

  factory _Biquad.lowPass(double fs, double fc) {
    final w = 2 * math.pi * fc / fs;
    final alpha = math.sin(w) / (2 * math.sqrt1_2);
    final cosw = math.cos(w);
    final a0 = 1 + alpha;
    return _Biquad(
      (1 - cosw) / 2 / a0,
      (1 - cosw) / a0,
      (1 - cosw) / 2 / a0,
      -2 * cosw / a0,
      (1 - alpha) / a0,
    );
  }

  factory _Biquad.highPass(double fs, double fc) {
    final w = 2 * math.pi * fc / fs;
    final alpha = math.sin(w) / (2 * math.sqrt1_2);
    final cosw = math.cos(w);
    final a0 = 1 + alpha;
    return _Biquad(
      (1 + cosw) / 2 / a0,
      -(1 + cosw) / a0,
      (1 + cosw) / 2 / a0,
      -2 * cosw / a0,
      (1 - alpha) / a0,
    );
  }

  final double b0, b1, b2, a1, a2;

  List<double> run(List<double> x) {
    final y = List<double>.filled(x.length, 0);
    var x1 = 0.0, x2 = 0.0, y1 = 0.0, y2 = 0.0;
    for (var i = 0; i < x.length; i++) {
      final v = b0 * x[i] + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2;
      x2 = x1;
      x1 = x[i];
      y2 = y1;
      y1 = v;
      y[i] = v;
    }
    return y;
  }
}
