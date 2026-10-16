import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hypertension/features/admin/data/admin_repository.dart';
import 'package:hypertension/features/admin/presentation/system_health_page.dart';
import 'package:hypertension/features/admin/state/admin_providers.dart';

import '../helpers/admin_fakes.dart';
import '../helpers/fakes.dart';

// Module 11 System Health (Fig 4.3.14.7; FR-11.3; D-59).

late FakeAdminRepository repo;

Widget host() => ProviderScope(
  overrides: [adminRepositoryProvider.overrideWithValue(repo)],
  child: const MaterialApp(home: Scaffold(body: SystemHealthPage())),
);

void main() {
  setUp(() {
    repo = FakeAdminRepository()
      ..health = SystemHealth(
        overall: 'degraded',
        uptime: 99.31,
        averageLatencyMs: 140,
        checkedAt: DateTime.utc(2026, 10, 16, 2),
        services: const [
          ServiceHealth(
            key: 'api',
            name: 'CareFlow API',
            status: 'operational',
            latencyMs: 0,
            uptime: 99.31,
          ),
          ServiceHealth(key: 'ml', name: 'ML risk model', status: 'degraded', latencyMs: 3400),
          ServiceHealth(
            key: 'grab',
            name: 'Grab delivery API',
            status: 'simulated',
            note: 'Simulated courier (about 1 min per stage).',
          ),
        ],
      );
  });

  tallTest('overview and one card per service with status, uptime and latency', (t) async {
    await t.pumpWidget(host());
    await t.pumpAndSettle();
    expect(find.text('Attention: Degraded'), findsOneWidget);
    expect(find.text('99.31%'), findsNWidgets(2));
    expect(find.text('140ms'), findsOneWidget);
    expect(find.text('Last checked: 10:00 AM MYT'), findsOneWidget);
    expect(
      find.descendant(of: find.byKey(const Key('service-ml')), matching: find.text('● Degraded')),
      findsOneWidget,
    );
    expect(find.text('3400ms'), findsOneWidget);
    expect(find.textContaining('Simulated courier'), findsOneWidget);
  });

  tallTest('refresh checks again', (t) async {
    await t.pumpWidget(host());
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('health-refresh')));
    await t.pumpAndSettle();
    expect(repo.calls.where((c) => c == 'health'), hasLength(2));
  });

  tallTest('all operational', (t) async {
    repo.health = const SystemHealth(overall: 'operational', services: []);
    await t.pumpWidget(host());
    await t.pumpAndSettle();
    expect(find.text('All systems operational'), findsOneWidget);
  });
}
