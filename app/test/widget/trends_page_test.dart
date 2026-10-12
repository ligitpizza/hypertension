import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hypertension/core/constants/enums.dart';
import 'package:hypertension/features/auth/state/auth_providers.dart';
import 'package:hypertension/features/charts/data/trends_repository.dart';
import 'package:hypertension/features/charts/presentation/trends_page.dart';
import 'package:hypertension/features/charts/state/trends_providers.dart';
import 'package:hypertension/features/dashboard/state/dashboard_providers.dart';
import 'package:hypertension/shared/models/health_models.dart';

import '../helpers/fakes.dart';

final now = DateTime(2026, 10, 13, 9);

/// Filters by the requested start date, like the Firestore query.
class FakeTrendsRepository implements TrendsRepository {
  FakeTrendsRepository(this.readings, {this.scores = const [], this.fail = false});

  final List<VitalReading> readings;
  final List<RiskScore> scores;
  final bool fail;

  @override
  Stream<List<VitalReading>> readingsSince(String patientId, DateTime from) {
    if (fail) return Stream.error(Exception('down'));
    final out = readings.where((r) => !r.timestamp.isBefore(from)).toList()
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return Stream.value(out);
  }

  @override
  Stream<List<RiskScore>> riskHistory(String patientId, {int limit = 60}) => Stream.value(scores);
}

VitalReading r(int sys, int dia, DateTime t, {int? hr}) => VitalReading(
  id: '$t',
  patientId: 'p1',
  systolic: sys,
  diastolic: dia,
  heartRate: hr,
  timestamp: t,
);

RiskScore score(DateTime t, double stroke) => RiskScore(
  id: '$t',
  patientId: 'p1',
  generatedAt: t,
  modelUsed: 'x',
  scores: {
    Complication.stroke: ComplicationScore(value: stroke, level: RiskLevel.moderate),
    Complication.cad: const ComplicationScore(value: 0.1, level: RiskLevel.low),
  },
);

Widget app(FakeTrendsRepository repo) {
  final router = GoRouter(
    initialLocation: '/trends',
    routes: [
      GoRoute(path: '/trends', builder: (_, _) => const TrendsPage()),
      GoRoute(path: '/vitals/log', builder: (_, _) => const Text('LOG PAGE')),
    ],
  );
  return ProviderScope(
    overrides: [
      trendsRepositoryProvider.overrideWithValue(repo),
      nowProvider.overrideWithValue(() => now),
      authUidProvider.overrideWith((ref) => Stream.value('p1')),
    ],
    child: MaterialApp.router(routerConfig: router),
  );
}

final weekReadings = [
  r(114, 72, DateTime(2026, 10, 8, 8), hr: 70),
  r(135, 88, DateTime(2026, 10, 10, 8)),
  r(118, 74, DateTime(2026, 10, 12, 8), hr: 74),
  r(150, 95, DateTime(2026, 8, 1, 8)), // only in 3M / 1Y
];

void main() {
  tallTest('Fig 4.3.4.2 fewer than three readings shows the empty state', (t) async {
    await t.pumpWidget(app(FakeTrendsRepository([r(128, 82, now, hr: 66)])));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('trends-not-enough')), findsOneWidget);
    expect(find.textContaining('Log 2 more readings'), findsOneWidget);
    expect(find.text('66 bpm'), findsOneWidget);
    expect(find.text('128/82'), findsOneWidget);
    expect(find.text('Pending Data'), findsOneWidget);
    await t.tap(find.byKey(const Key('trends-log-now')));
    await t.pumpAndSettle();
    expect(find.text('LOG PAGE'), findsOneWidget);
  });

  tallTest('FR-4.1 FR-4.2 7D chart with latest reading and avg/min/max', (t) async {
    await t.pumpWidget(app(FakeTrendsRepository(weekReadings)));
    await t.pumpAndSettle();
    expect(find.text('Latest Reading'), findsOneWidget);
    expect(find.byKey(const Key('bp-trend-chart')), findsOneWidget);
    expect(find.text('122/78'), findsOneWidget); // avg of the 3 in-range readings
    expect(find.text('114/72'), findsOneWidget); // min
    expect(find.text('135/88'), findsOneWidget); // max
    expect(find.textContaining('3 readings'), findsOneWidget);
    expect(find.textContaining('systolic up 4 mmHg'), findsOneWidget);
  });

  tallTest('UC4.1 A1 switching to 3M re-renders in place with daily averages', (t) async {
    await t.pumpWidget(app(FakeTrendsRepository(weekReadings)));
    await t.pumpAndSettle();
    await t.tap(find.text('3M'));
    await t.pumpAndSettle();
    expect(find.textContaining('4 readings'), findsOneWidget);
    expect(find.text('Each point is a daily average.'), findsOneWidget);
    expect(find.text('150/95'), findsOneWidget); // new max
  });

  tallTest('UC4.1 E1 a range without readings shows a message', (t) async {
    final old = [
      r(120, 80, DateTime(2026, 9, 1)),
      r(122, 81, DateTime(2026, 9, 2)),
      r(125, 82, DateTime(2026, 9, 3)),
    ];
    await t.pumpWidget(app(FakeTrendsRepository(old)));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('trend-range-empty')), findsOneWidget);
  });

  tallTest('UC4.3 compare heart rate overlays the second vital', (t) async {
    await t.pumpWidget(app(FakeTrendsRepository(weekReadings)));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('compare-hr')));
    await t.pumpAndSettle();
    expect(find.text('Heart rate'), findsOneWidget); // legend
    expect(find.byKey(const Key('hr-missing')), findsNothing);
    expect(find.textContaining('avg heart rate 72 bpm'), findsOneWidget);
  });

  tallTest('UC4.3 E1 no heart-rate data shows BP only with a note', (t) async {
    final noHr = [for (final x in weekReadings) r(x.systolic, x.diastolic, x.timestamp)];
    await t.pumpWidget(app(FakeTrendsRepository(noHr)));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('compare-hr')));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('hr-missing')), findsOneWidget);
  });

  tallTest('FR-4.3 UC4.4 risk trend: empty, single score, and chart', (t) async {
    await t.pumpWidget(app(FakeTrendsRepository(weekReadings)));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('risk-trend-empty')), findsOneWidget);

    await t.pumpWidget(app(FakeTrendsRepository(weekReadings, scores: [score(now, 0.3)])));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('risk-trend-single')), findsOneWidget); // UC4.4 E1
    expect(find.text('Stroke: 30%'), findsOneWidget);

    await t.pumpWidget(
      app(
        FakeTrendsRepository(
          weekReadings,
          scores: [score(now, 0.3), score(now.subtract(const Duration(days: 5)), 0.2)],
        ),
      ),
    );
    await t.pumpAndSettle();
    expect(find.byKey(const Key('risk-trend-chart')), findsOneWidget);
    expect(find.text('Coronary artery disease'), findsOneWidget);
  });

  tallTest('error state offers retry', (t) async {
    await t.pumpWidget(app(FakeTrendsRepository(const [], fail: true)));
    await t.pumpAndSettle();
    expect(find.text('Could not load your readings.'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
  });
}
