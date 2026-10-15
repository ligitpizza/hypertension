import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hypertension/core/constants/enums.dart';
import 'package:hypertension/features/admin/data/analytics_models.dart';
import 'package:hypertension/features/admin/presentation/hospital_analytics_page.dart';
import 'package:hypertension/features/admin/presentation/system_analytics_page.dart';
import 'package:hypertension/features/admin/state/admin_providers.dart';
import 'package:hypertension/features/dashboard/state/dashboard_providers.dart';
import 'package:hypertension/features/settings/data/settings_repository.dart';
import 'package:hypertension/features/settings/state/settings_providers.dart';
import 'package:hypertension/shared/services/api/api_client.dart';

import '../helpers/admin_fakes.dart';
import '../helpers/fakes.dart';

// Module 11 analytics and report (Figs 4.3.14.5-4.3.14.6; FR-11.3, FR-11.4, UC11.5; D-59).

final now = DateTime.utc(2026, 10, 16, 4); // 12:00 MYT

RiskCounts counts(int low, int mod, int high, int crit) => RiskCounts({
  RiskLevel.low: low,
  RiskLevel.moderate: mod,
  RiskLevel.high: high,
  RiskLevel.critical: crit,
});

class FakeSharer implements FileSharer {
  final shared = <String>[];

  @override
  Future<void> share(Uint8List bytes, {required String fileName, required String mimeType}) async =>
      shared.add('$fileName|$mimeType');
}

late FakeAdminRepository repo;
late FakeSharer sharer;

Widget host(Widget page) => ProviderScope(
  overrides: [
    adminRepositoryProvider.overrideWithValue(repo),
    fileSharerProvider.overrideWithValue(sharer),
    nowProvider.overrideWithValue(() => now),
  ],
  child: MaterialApp(home: Scaffold(body: page)),
);

void main() {
  setUp(() {
    sharer = FakeSharer();
    repo = FakeAdminRepository()
      ..hospital = HospitalAnalytics(
        activePatients: 12,
        risk: counts(5, 3, 1, 1),
        riskTrend: [
          MonthRisk('2026-09', counts(4, 2, 1, 0)),
          MonthRisk('2026-10', counts(5, 3, 1, 1)),
        ],
        consultations: const [
          MonthConsultations(month: '2026-09', completed: 8, noShow: 1, cancelled: 2, upcoming: 0),
          MonthConsultations(month: '2026-10', completed: 5, noShow: 0, cancelled: 1, upcoming: 4),
        ],
        adherence: 87.4,
        adherenceDaily: [(DateTime(2026, 10, 14), 80.0), (DateTime(2026, 10, 15), 90.0)],
      )
      ..usage = SystemAnalytics(
        days: 7,
        activeClinicians: 3,
        totalClinicians: 4,
        messagesSent: 42,
        messagesPerDay: 6,
        unresolvedCritical: 2,
        totalUsers: 25,
        uptime: 99.5,
        dailyActivity: [
          (DateTime(2026, 10, 15), {'patient': 10, 'doctor': 4}),
          (DateTime(2026, 10, 16), {'patient': 6}),
        ],
        bySpecialty: const [('Cardiology', 12), ('General', 4)],
      );
  });

  group('Fig 4.3.14.5 hospital analytics', () {
    tallTest('risk distribution, trend, consultations, adherence; delivery waits', (t) async {
      await t.pumpWidget(host(const HospitalAnalyticsPage()));
      await t.pumpAndSettle();
      expect(
        find.descendant(of: find.byKey(const Key('panel-risk')), matching: find.text('10')),
        findsOneWidget,
      ); // assessed patients in the donut
      expect(find.text('of 12 patients'), findsOneWidget);
      expect(find.text('Low 5 (50%)'), findsOneWidget);
      expect(find.text('Critical 1 (10%)'), findsOneWidget);
      expect(find.byKey(const Key('panel-risk-trend')), findsOneWidget);
      expect(find.text('Oct'), findsWidgets);
      expect(find.text('87%'), findsOneWidget);
      expect(find.textContaining('Module 13'), findsOneWidget);
    });

    tallTest('UC11.5 generate the report for a chosen period', (t) async {
      await t.pumpWidget(host(const HospitalAnalyticsPage()));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('generate-report')));
      await t.pumpAndSettle();
      await t.tap(find.text('Save'));
      await t.pumpAndSettle();
      expect(repo.calls.last, 'report:2026-09-17:2026-10-16');
      expect(sharer.shared, ['careflow-hospital-report.pdf|application/pdf']);
    });

    tallTest('UC11.5 E1 no data shows the message instead of a file', (t) async {
      repo.error = ApiException('NO_DATA', 'There is no activity in this period.');
      await t.pumpWidget(host(const HospitalAnalyticsPage()));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('generate-report')));
      await t.pumpAndSettle();
      await t.tap(find.text('Save'));
      await t.pumpAndSettle();
      expect(find.text('There is no activity in this period.'), findsOneWidget);
      expect(sharer.shared, isEmpty);
    });
  });

  group('Fig 4.3.14.6 usage analytics', () {
    tallTest('headline numbers, engagement and specialty breakdown', (t) async {
      await t.pumpWidget(host(const SystemAnalyticsPage()));
      await t.pumpAndSettle();
      expect(find.text('of 4 in the last 7 days'), findsOneWidget);
      expect(find.text('99.5%'), findsOneWidget);
      expect(find.text('42'), findsOneWidget);
      expect(find.text('6.0 per day (encrypted)'), findsOneWidget);
      expect(find.byKey(const Key('panel-engagement')), findsOneWidget);
      expect(find.text('THU'), findsOneWidget);
      expect(find.text('25'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const Key('specialty-Cardiology')),
          matching: find.text('75%'),
        ),
        findsOneWidget,
      );
    });

    tallTest('switching to 30 days reloads', (t) async {
      await t.pumpWidget(host(const SystemAnalyticsPage()));
      await t.pumpAndSettle();
      await t.tap(find.text('30D'));
      await t.pumpAndSettle();
      expect(repo.calls, containsAllInOrder(['usage:7', 'usage:30']));
    });
  });

  test('month labels', () => expect(monthShort('2026-10'), 'Oct'));
}
