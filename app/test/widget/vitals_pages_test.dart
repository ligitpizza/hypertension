import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hypertension/core/constants/enums.dart';
import 'package:hypertension/features/auth/state/auth_providers.dart';
import 'package:hypertension/features/dashboard/state/dashboard_providers.dart';
import 'package:hypertension/features/vitals/data/ppg_capture.dart';
import 'package:hypertension/features/vitals/data/vitals_repository.dart';
import 'package:hypertension/features/vitals/domain/ppg.dart';
import 'package:hypertension/features/vitals/presentation/log_vitals_page.dart';
import 'package:hypertension/features/vitals/presentation/reading_saved_page.dart';
import 'package:hypertension/features/vitals/presentation/vitals_page.dart';
import 'package:hypertension/features/vitals/state/vitals_providers.dart';
import 'package:hypertension/shared/models/health_models.dart';
import 'package:hypertension/shared/services/api/api_client.dart';

import '../helpers/fakes.dart';
import 'dashboard_page_test.dart' show FakeDashboardRepository;

final now = DateTime(2026, 10, 12, 8, 42);

class FakeVitalsRepository implements VitalsRepository {
  Object? error;
  Map<String, Object?>? last;

  @override
  Future<LoggedReading> logReading({
    required int systolic,
    required int diastolic,
    int? heartRate,
    String? note,
  }) async {
    last = {'systolic': systolic, 'diastolic': diastolic, 'heartRate': heartRate, 'note': note};
    if (error != null) throw error!;
    return LoggedReading(
      id: 'r1',
      systolic: systolic,
      diastolic: diastolic,
      heartRate: heartRate,
      category: BpCategory.normal,
      loggedAt: now,
    );
  }
}

class FakePpgCapture implements PpgCapture {
  PpgResult result = const PpgResult.success(72, 0.9);
  PpgUnavailable? unavailable;
  int calls = 0;
  bool cancelled = false;

  @override
  Future<PpgResult> measure({required PpgProgress onProgress, Duration? duration}) async {
    calls++;
    if (unavailable != null) throw PpgUnavailableException(unavailable!);
    onProgress(0.5, const [1, 2, 3, 2, 1]);
    return result;
  }

  @override
  Future<void> cancel() async => cancelled = true;
}

Widget logApp(FakeVitalsRepository repo, FakePpgCapture ppg) {
  final router = GoRouter(
    initialLocation: '/vitals/log',
    routes: [
      GoRoute(path: '/vitals/log', builder: (_, _) => const LogVitalsPage()),
      GoRoute(
        path: '/vitals/saved',
        builder: (_, s) => Text('SAVED ${(s.extra! as LoggedReading).systolic}'),
      ),
    ],
  );
  return ProviderScope(
    overrides: [
      vitalsRepositoryProvider.overrideWithValue(repo),
      ppgCaptureProvider.overrideWithValue(ppg),
    ],
    child: MaterialApp.router(routerConfig: router),
  );
}

Future<void> enterBp(WidgetTester t, String sys, String dia) async {
  await t.enterText(find.byKey(const Key('bp-systolic')), sys);
  await t.enterText(find.byKey(const Key('bp-diastolic')), dia);
}

void main() {
  group('UC3.1 Log Vitals (Fig 4.3.3.2)', () {
    tallTest('FR-3.1 saves a reading with a note and opens the saved screen', (t) async {
      final repo = FakeVitalsRepository();
      await t.pumpWidget(logApp(repo, FakePpgCapture()));
      await enterBp(t, '128', '82');
      await t.enterText(find.byKey(const Key('bp-note')), 'after walk');
      await t.tap(find.byKey(const Key('bp-save')));
      await t.pumpAndSettle();
      expect(repo.last, {
        'systolic': 128,
        'diastolic': 82,
        'heartRate': null,
        'note': 'after walk',
      });
      expect(find.text('SAVED 128'), findsOneWidget);
    });

    tallTest('blocks save when values are missing', (t) async {
      final repo = FakeVitalsRepository();
      await t.pumpWidget(logApp(repo, FakePpgCapture()));
      await t.tap(find.byKey(const Key('bp-save')));
      await t.pump();
      expect(find.text('Enter your systolic (top) number'), findsOneWidget);
      expect(repo.last, isNull);
    });

    tallTest('UC3.1 E1 implausible reading asks the patient to re-check', (t) async {
      final repo = FakeVitalsRepository();
      await t.pumpWidget(logApp(repo, FakePpgCapture()));
      await enterBp(t, '400', '80');
      await t.tap(find.byKey(const Key('bp-save')));
      await t.pump();
      expect(find.textContaining('re-check'), findsOneWidget);
      expect(repo.last, isNull);
    });

    tallTest('UC3.1 E1 server rejection is shown', (t) async {
      final repo = FakeVitalsRepository()
        ..error = ApiException('READING_OUT_OF_RANGE', 'Systolic must be between 70 and 250 mmHg.');
      await t.pumpWidget(logApp(repo, FakePpgCapture()));
      await enterBp(t, '120', '80');
      await t.tap(find.byKey(const Key('bp-save')));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('bp-error')), findsOneWidget);
    });

    tallTest('network failure says the reading was not saved', (t) async {
      final repo = FakeVitalsRepository()..error = ApiException('NETWORK_ERROR', 'x');
      await t.pumpWidget(logApp(repo, FakePpgCapture()));
      await enterBp(t, '120', '80');
      await t.tap(find.byKey(const Key('bp-save')));
      await t.pumpAndSettle();
      expect(find.textContaining('was not saved'), findsOneWidget);
    });
  });

  group('UC3.3 camera heart rate', () {
    tallTest('FR-3.2 measured heart rate is shown as an estimate and saved', (t) async {
      final repo = FakeVitalsRepository();
      final ppg = FakePpgCapture();
      await t.pumpWidget(logApp(repo, ppg));
      await t.tap(find.byKey(const Key('ppg-start')));
      await t.pumpAndSettle();
      expect(find.text('72 BPM'), findsOneWidget);
      expect(find.textContaining('Estimate'), findsOneWidget);
      expect(find.byKey(const Key('bp-hr-attached')), findsOneWidget);
      await enterBp(t, '118', '76');
      await t.tap(find.byKey(const Key('bp-save')));
      await t.pumpAndSettle();
      expect(repo.last!['heartRate'], 72);
    });

    tallTest('UC3.3 E1 poor signal offers retry and skip', (t) async {
      final ppg = FakePpgCapture()..result = const PpgResult.failed(PpgFailure.irregular);
      await t.pumpWidget(logApp(FakeVitalsRepository(), ppg));
      await t.tap(find.byKey(const Key('ppg-start')));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('ppg-failed')), findsOneWidget);
      await t.tap(find.byKey(const Key('ppg-retry')));
      await t.pumpAndSettle();
      expect(ppg.calls, 2);
      await t.tap(find.byKey(const Key('ppg-skip')));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('ppg-start')), findsOneWidget);
      expect(find.byKey(const Key('bp-hr-attached')), findsNothing);
    });

    tallTest('no camera: manual heart-rate entry is offered and saved', (t) async {
      final repo = FakeVitalsRepository();
      final ppg = FakePpgCapture()..unavailable = PpgUnavailable.noCamera;
      await t.pumpWidget(logApp(repo, ppg));
      await t.tap(find.byKey(const Key('ppg-start')));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('ppg-unavailable')), findsOneWidget);
      await t.tap(find.text('Enter manually'));
      await t.pumpAndSettle();
      await t.enterText(find.byKey(const Key('hr-manual-input')), '66');
      await enterBp(t, '118', '76');
      await t.tap(find.byKey(const Key('bp-save')));
      await t.pumpAndSettle();
      expect(repo.last!['heartRate'], 66);
    });

    tallTest('implausible manual heart rate is not attached', (t) async {
      final repo = FakeVitalsRepository();
      await t.pumpWidget(logApp(repo, FakePpgCapture()));
      await t.tap(find.byKey(const Key('ppg-manual')));
      await t.pumpAndSettle();
      await t.enterText(find.byKey(const Key('hr-manual-input')), '400');
      await t.pump();
      expect(find.byKey(const Key('bp-hr-attached')), findsNothing);
    });
  });

  group('Fig 4.3.3.3 Reading Saved', () {
    Widget saved(LoggedReading r) => MaterialApp(home: ReadingSavedPage(reading: r));

    tallTest('shows value, category badge and heart rate', (t) async {
      await t.pumpWidget(
        saved(
          LoggedReading(
            id: 'r',
            systolic: 120,
            diastolic: 80,
            heartRate: 72,
            category: BpCategory.stage1,
            loggedAt: now,
          ),
        ),
      );
      expect(find.text('120/80 mmHg'), findsOneWidget);
      expect(find.text('High — Stage 1'), findsOneWidget);
      expect(find.text('Today, 8:42 AM'), findsOneWidget);
      expect(find.text('72 BPM'), findsOneWidget);
      expect(find.text('Great job logging!'), findsOneWidget);
      expect(find.byKey(const Key('crisis-banner')), findsNothing);
    });

    tallTest('crisis reading shows the 999 safety banner', (t) async {
      await t.pumpWidget(
        saved(
          LoggedReading(
            id: 'r',
            systolic: 185,
            diastolic: 110,
            category: BpCategory.crisis,
            alertLevel: AlertLevel.emergency,
            loggedAt: now,
          ),
        ),
      );
      expect(find.byKey(const Key('crisis-banner')), findsOneWidget);
      expect(find.textContaining('call 999'), findsOneWidget);
      expect(find.byKey(const Key('saved-hr')), findsNothing);
    });
  });

  group('Fig 4.3.3.1 Vitals tab', () {
    Widget tab(FakeDashboardRepository repo) => ProviderScope(
      overrides: [
        dashboardRepositoryProvider.overrideWithValue(repo),
        nowProvider.overrideWithValue(() => now),
        authUidProvider.overrideWith((ref) => Stream.value('p1')),
      ],
      child: const MaterialApp(home: VitalsPage()),
    );

    tallTest('empty state prompts the first reading and shows 0/3', (t) async {
      await t.pumpWidget(tab(FakeDashboardRepository()));
      await t.pumpAndSettle();
      expect(find.text('-- / --  mmHg'), findsOneWidget);
      expect(find.byKey(const Key('vitals-empty')), findsOneWidget);
      expect(find.text('0/3 readings'), findsOneWidget);
    });

    tallTest('shows latest reading with category and recent history', (t) async {
      final repo = FakeDashboardRepository()
        ..readings = Stream.value([
          VitalReading(id: 'a', patientId: 'p1', systolic: 142, diastolic: 91, timestamp: now),
          VitalReading(
            id: 'b',
            patientId: 'p1',
            systolic: 118,
            diastolic: 76,
            heartRate: 70,
            note: 'morning',
            timestamp: now.subtract(const Duration(days: 1)),
          ),
        ]);
      await t.pumpWidget(tab(repo));
      await t.pumpAndSettle();
      expect(find.text('142 / 91  mmHg'), findsOneWidget);
      expect(find.text('High — Stage 2'), findsWidgets);
      expect(find.text('2/3 readings'), findsOneWidget);
      expect(find.text('118/76 mmHg · 70 bpm'), findsOneWidget);
      expect(find.textContaining('morning'), findsOneWidget);
    });

    tallTest('error state offers retry', (t) async {
      final repo = FakeDashboardRepository()..readings = Stream.error(Exception('x'));
      await t.pumpWidget(tab(repo));
      await t.pumpAndSettle();
      expect(find.text('Could not load your readings.'), findsOneWidget);
    });

    tallTest('loading state', (t) async {
      final c = StreamController<List<VitalReading>>();
      addTearDown(c.close);
      await t.pumpWidget(tab(FakeDashboardRepository()..readings = c.stream));
      await t.pump();
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });
  });
}
