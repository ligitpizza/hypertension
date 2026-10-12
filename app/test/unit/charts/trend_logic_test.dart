import 'package:flutter_test/flutter_test.dart';
import 'package:hypertension/core/constants/enums.dart';
import 'package:hypertension/features/charts/domain/trend_logic.dart';
import 'package:hypertension/shared/models/health_models.dart';

final now = DateTime(2026, 10, 13, 9);

VitalReading r(int sys, int dia, DateTime t, {int? hr}) => VitalReading(
  id: '$t',
  patientId: 'p',
  systolic: sys,
  diastolic: dia,
  heartRate: hr,
  timestamp: t,
);

void main() {
  group('FR-4.1 ranges', () {
    test('7D, 30D, 3M and 1Y windows start at local midnight', () {
      expect(TrendRange.week.startFrom(now), DateTime(2026, 10, 7));
      expect(TrendRange.month.startFrom(now), DateTime(2026, 9, 14));
      expect(TrendRange.quarter.startFrom(now), DateTime(2026, 7, 16));
      expect(TrendRange.year.startFrom(now), DateTime(2025, 10, 14));
      expect(TrendRange.values.map((e) => e.label), ['7D', '30D', '3M', '1Y']);
    });

    test('short ranges plot raw readings in time order, excluding older ones', () {
      final readings = [
        r(130, 85, now.subtract(const Duration(hours: 1))),
        r(120, 80, DateTime(2026, 10, 8, 7)),
        r(150, 95, DateTime(2026, 10, 1)), // outside 7D
      ];
      final pts = buildPoints(readings, TrendRange.week, now);
      expect(pts.map((p) => p.systolic), [120, 130]);
    });

    test('3M and 1Y plot one averaged point per day', () {
      final readings = [
        r(120, 80, DateTime(2026, 10, 12, 8), hr: 60),
        r(140, 90, DateTime(2026, 10, 12, 20)),
        r(130, 84, DateTime(2026, 9, 1, 9), hr: 70),
      ];
      final pts = buildPoints(readings, TrendRange.quarter, now);
      expect(pts.length, 2);
      expect(pts.first.time, DateTime(2026, 9, 1));
      expect((pts.last.systolic, pts.last.diastolic, pts.last.heartRate), (130.0, 85.0, 60.0));
    });
  });

  group('FR-4.2 statistics', () {
    test('average, min and max pairs over the range', () {
      final readings = [
        r(114, 72, DateTime(2026, 10, 8)),
        r(135, 88, DateTime(2026, 10, 10), hr: 70),
        r(118, 74, DateTime(2026, 10, 12), hr: 74),
      ];
      final s = computeStats(readings, TrendRange.week, now)!;
      expect(s.count, 3);
      expect((s.avgSystolic, s.avgDiastolic), (122, 78));
      expect((s.min.systolic, s.min.diastolic), (114, 72));
      expect((s.max.systolic, s.max.diastolic), (135, 88));
      expect(s.avgHeartRate, 72);
      expect(s.systolicChange, 4);
    });

    test('UC4.2 E1 a single reading has values but no trend', () {
      final s = computeStats([r(128, 82, now)], TrendRange.week, now)!;
      expect(s.avgSystolic, 128);
      expect(s.hasTrend, isFalse);
      expect(s.avgHeartRate, isNull);
    });

    test('UC4.1 E1 no readings in range gives no stats', () {
      expect(computeStats([r(120, 80, DateTime(2025, 1, 1))], TrendRange.week, now), isNull);
    });
  });

  test('UC4.3 E1 detects missing heart-rate data', () {
    final with_ = buildPoints([r(120, 80, now, hr: 60)], TrendRange.week, now);
    final without = buildPoints([r(120, 80, now)], TrendRange.week, now);
    expect(hasHeartRate(with_), isTrue);
    expect(hasHeartRate(without), isFalse);
  });

  test('FR-4.3 UC4.4 risk history becomes one time-ordered series per complication', () {
    RiskScore score(DateTime t, double stroke, double cad) => RiskScore(
      id: '$t',
      patientId: 'p',
      generatedAt: t,
      modelUsed: 'x',
      scores: {
        Complication.stroke: ComplicationScore(value: stroke, level: RiskLevel.low),
        Complication.cad: ComplicationScore(value: cad, level: RiskLevel.moderate),
      },
    );
    final series = riskSeries([
      score(DateTime(2026, 10, 10), 0.2, 0.4),
      score(DateTime(2026, 10, 1), 0.1, 0.3),
    ]);
    expect(series[Complication.stroke]!.map((e) => e.$2), [0.1, 0.2]);
    expect(series[Complication.cad]!.first.$1, DateTime(2026, 10, 1));
    expect(series.containsKey(Complication.ckd), isFalse);
  });
}
