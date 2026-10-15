import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hypertension/features/admin/data/admin_repository.dart';
import 'package:hypertension/features/admin/presentation/audit_logs_page.dart';
import 'package:hypertension/features/admin/state/admin_providers.dart';
import 'package:hypertension/features/dashboard/state/dashboard_providers.dart';
import 'package:hypertension/features/settings/data/settings_repository.dart';
import 'package:hypertension/features/settings/state/settings_providers.dart';

import '../helpers/admin_fakes.dart';
import '../helpers/fakes.dart';

// Module 11 Security & Audit Logs (Fig 4.3.14.3; FR-1.5, FR-11.3, UC11.3; D-59).

/// Thu 15 Oct 2026, 12:00 Malaysia time.
final now = DateTime.utc(2026, 10, 15, 4);

class FakeSharer implements FileSharer {
  final shared = <String>[];

  @override
  Future<void> share(Uint8List bytes, {required String fileName, required String mimeType}) async =>
      shared.add('$fileName|$mimeType');
}

late FakeAdminRepository repo;
late FakeSharer sharer;

Widget host() => ProviderScope(
  overrides: [
    adminRepositoryProvider.overrideWithValue(repo),
    fileSharerProvider.overrideWithValue(sharer),
    nowProvider.overrideWithValue(() => now),
  ],
  child: const MaterialApp(home: Scaffold(body: AuditLogsPage())),
);

void main() {
  setUp(() {
    sharer = FakeSharer();
    repo = FakeAdminRepository()
      ..audit = AuditPage(
        total: 32,
        actions: const ['DEACTIVATE_ACCOUNT', 'LOGIN_FAILED'],
        summary: const {
          'totalEvents': 32,
          'changeFromPrevious': 12,
          'failedLogins': 4,
          'privilegeChanges': 2,
          'dataExports': 1,
        },
        entries: [
          AuditEntry(
            id: 'l1',
            action: 'DEACTIVATE_ACCOUNT',
            module: 'Accounts',
            details: 'Deactivated pharmacist account.',
            timestamp: DateTime.utc(2026, 10, 15, 2, 15),
            userId: 'u-admin',
            userName: 'Ada Admin',
            role: 'admin',
          ),
          AuditEntry(
            id: 'l2',
            action: 'LOGIN_FAILED',
            module: 'Authentication',
            details: 'app=staff; reason=wrong_password',
            timestamp: DateTime.utc(2026, 10, 15, 1),
            userId: 'anonymous',
          ),
        ],
      );
  });

  tallTest('summary cards, entries with module and MYT time', (t) async {
    await t.pumpWidget(host());
    await t.pumpAndSettle();
    expect(find.text('Security & Audit Logs'), findsOneWidget);
    expect(find.text('↑ 12% from the previous 7 days'), findsOneWidget);
    expect(
      find.descendant(of: find.byKey(const Key('sum-failed')), matching: find.text('4')),
      findsOneWidget,
    );
    expect(find.text('Deactivate account'), findsOneWidget);
    expect(find.textContaining('Ada Admin · admin'), findsOneWidget);
    expect(find.textContaining('Unauthenticated'), findsOneWidget);
    expect(find.text('Thu 15 Oct\n10:15 AM MYT'), findsOneWidget);
    expect(find.text('Showing 1-2 of 32'), findsOneWidget);
    // Last 7 days ending today (MYT).
    final q = repo.auditQueries.last;
    expect((q.from, q.to), (DateTime(2026, 10, 9), DateTime(2026, 10, 15)));
  });

  tallTest('UC11.3 filter by range, action and text; page forward', (t) async {
    await t.pumpWidget(host());
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('audit-range')));
    await t.pumpAndSettle();
    await t.tap(find.text('Last 30 days').last);
    await t.pumpAndSettle();
    expect(repo.auditQueries.last.from, DateTime(2026, 9, 16));
    await t.tap(find.byKey(const Key('audit-action')));
    await t.pumpAndSettle();
    await t.tap(find.text('Login failed').last);
    await t.pumpAndSettle();
    expect(repo.auditQueries.last.action, 'LOGIN_FAILED');
    await t.enterText(find.byKey(const Key('audit-search')), 'ada');
    await t.testTextInput.receiveAction(TextInputAction.done);
    await t.pumpAndSettle();
    expect(repo.auditQueries.last.text, 'ada');
    await t.tap(find.byKey(const Key('audit-next')));
    await t.pumpAndSettle();
    expect(repo.auditQueries.last.offset, 15);
  });

  tallTest('FR-11.3 export CSV with the current filters', (t) async {
    await t.pumpWidget(host());
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('audit-export')));
    await t.pumpAndSettle();
    expect(repo.calls, ['csv:null']);
    expect(sharer.shared, ['careflow-audit-log.csv|text/csv']);
  });

  tallTest('empty result', (t) async {
    repo.audit = const AuditPage(entries: [], total: 0, actions: [], summary: {});
    await t.pumpWidget(host());
    await t.pumpAndSettle();
    expect(find.byKey(const Key('audit-empty')), findsOneWidget);
    expect(find.text('No earlier period to compare'), findsOneWidget);
  });

  test('action labels', () {
    expect(actionLabel('DEACTIVATE_ACCOUNT'), 'Deactivate account');
    expect(actionLabel('LOGIN'), 'Login');
  });
}
