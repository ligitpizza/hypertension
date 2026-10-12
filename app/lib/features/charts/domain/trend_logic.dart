import '../../../core/constants/enums.dart';
import '../../../shared/models/health_models.dart';

/// Timeframes for the BP trend chart (FR-4.1: 7-day, 30-day, 3-month, 1-year).
enum TrendRange {
  week('7D', 7),
  month('30D', 30),
  quarter('3M', 90),
  year('1Y', 365);

  const TrendRange(this.label, this.days);
  final String label;
  final int days;

  /// Start of the window: midnight [days - 1] days before today, so "7D" is today
  /// plus the six previous days.
  DateTime startFrom(DateTime now) =>
      DateTime(now.year, now.month, now.day).subtract(Duration(days: days - 1));

  /// Long ranges plot one averaged point per day so a year stays readable.
  bool get dailyAverages => days > 30;
}

/// One plotted point. Daily-averaged points use local midnight as [time].
class TrendPoint {
  const TrendPoint(this.time, this.systolic, this.diastolic, this.heartRate);

  final DateTime time;
  final double systolic;
  final double diastolic;
  final double? heartRate;
}

/// Readings (any order) inside [range] -> points in time order.
List<TrendPoint> buildPoints(List<VitalReading> readings, TrendRange range, DateTime now) {
  final start = range.startFrom(now);
  final inRange = readings.where((r) => !r.timestamp.isBefore(start)).toList()
    ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
  if (!range.dailyAverages) {
    return [
      for (final r in inRange)
        TrendPoint(
          r.timestamp,
          r.systolic.toDouble(),
          r.diastolic.toDouble(),
          r.heartRate?.toDouble(),
        ),
    ];
  }
  final byDay = <DateTime, List<VitalReading>>{};
  for (final r in inRange) {
    final day = DateTime(r.timestamp.year, r.timestamp.month, r.timestamp.day);
    (byDay[day] ??= []).add(r);
  }
  final days = byDay.keys.toList()..sort();
  return [
    for (final d in days)
      TrendPoint(
        d,
        _avg(byDay[d]!.map((r) => r.systolic)),
        _avg(byDay[d]!.map((r) => r.diastolic)),
        _avgOrNull(byDay[d]!.map((r) => r.heartRate).whereType<int>()),
      ),
  ];
}

/// FR-4.2 / UC4.2 statistics for the readings in a range.
class BpStats {
  const BpStats({
    required this.count,
    required this.avgSystolic,
    required this.avgDiastolic,
    required this.min,
    required this.max,
    required this.avgHeartRate,
    required this.systolicChange,
  });

  final int count;
  final int avgSystolic;
  final int avgDiastolic;

  /// Reading with the lowest / highest systolic ("114/72", "135/88" in Fig 4.3.4.1).
  final VitalReading min;
  final VitalReading max;
  final int? avgHeartRate;

  /// Last minus first systolic in the range; null with fewer than two readings
  /// (UC4.2 E1: omit trend-based statistics).
  final int? systolicChange;

  bool get hasTrend => systolicChange != null;
}

BpStats? computeStats(List<VitalReading> readings, TrendRange range, DateTime now) {
  final start = range.startFrom(now);
  final inRange = readings.where((r) => !r.timestamp.isBefore(start)).toList()
    ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
  if (inRange.isEmpty) return null;
  var min = inRange.first;
  var max = inRange.first;
  for (final r in inRange) {
    if (r.systolic < min.systolic) min = r;
    if (r.systolic > max.systolic) max = r;
  }
  final hr = inRange.map((r) => r.heartRate).whereType<int>();
  return BpStats(
    count: inRange.length,
    avgSystolic: _avg(inRange.map((r) => r.systolic)).round(),
    avgDiastolic: _avg(inRange.map((r) => r.diastolic)).round(),
    min: min,
    max: max,
    avgHeartRate: hr.isEmpty ? null : _avg(hr).round(),
    systolicChange: inRange.length < 2 ? null : inRange.last.systolic - inRange.first.systolic,
  );
}

/// UC4.3 E1: the second vital has no data in range.
bool hasHeartRate(List<TrendPoint> points) => points.any((p) => p.heartRate != null);

/// UC4.4: per-complication risk history in time order.
Map<Complication, List<(DateTime, double)>> riskSeries(List<RiskScore> scores) {
  final ordered = [...scores]..sort((a, b) => a.generatedAt.compareTo(b.generatedAt));
  final out = <Complication, List<(DateTime, double)>>{};
  for (final s in ordered) {
    for (final e in s.scores.entries) {
      (out[e.key] ??= []).add((s.generatedAt, e.value.value));
    }
  }
  return out;
}

double _avg(Iterable<int> v) => v.reduce((a, b) => a + b) / v.length;

double? _avgOrNull(Iterable<int> v) => v.isEmpty ? null : _avg(v);
