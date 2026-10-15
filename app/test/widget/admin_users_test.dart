import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hypertension/core/constants/enums.dart';
import 'package:hypertension/features/admin/presentation/admin_users_page.dart';
import 'package:hypertension/features/admin/state/admin_providers.dart';
import 'package:hypertension/shared/services/api/api_client.dart';

import '../helpers/admin_fakes.dart';
import '../helpers/fakes.dart';

// Module 11 User Management (Fig 4.3.14.1; FR-11.1, UC11.1; D-59).

late FakeAdminRepository repo;

Widget host() {
  final router = GoRouter(
    initialLocation: '/admin/users',
    routes: [
      GoRoute(
        path: '/admin/users',
        builder: (_, _) => const Scaffold(body: AdminUsersPage()),
        routes: [GoRoute(path: 'new', builder: (_, _) => const Text('ADD STAFF'))],
      ),
    ],
  );
  return ProviderScope(
    overrides: [adminRepositoryProvider.overrideWithValue(repo)],
    child: MaterialApp.router(routerConfig: router),
  );
}

Future<void> menu(WidgetTester t, String uid, String item) async {
  await t.tap(find.byKey(Key('user-menu-$uid')));
  await t.pumpAndSettle();
  await t.tap(find.text(item).last);
  await t.pumpAndSettle();
}

void main() {
  setUp(() {
    repo = FakeAdminRepository()
      ..all = [
        user('d1', 'Dr John', UserRole.doctor, caseload: 12),
        user('p1', 'Siti Aminah', UserRole.patient),
        user('p2', 'Ali Bakar', UserRole.patient, active: false),
        user('a1', 'Ada Admin', UserRole.admin),
      ];
  });

  tallTest('lists users with role, status and the doctor caseload', (t) async {
    await t.pumpWidget(host());
    await t.pumpAndSettle();
    expect(find.text('User Management'), findsOneWidget);
    expect(find.textContaining('Cardiology · 12 / 30 patients'), findsOneWidget);
    expect(find.text('● Deactivated'), findsOneWidget);
    expect(find.text('Showing 1 to 4 of 4 entries'), findsOneWidget);
  });

  tallTest('UC11.1 step 1: filter by role and search', (t) async {
    await t.pumpWidget(host());
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('role-filter')));
    await t.pumpAndSettle();
    await t.tap(find.text('Patient').last);
    await t.pumpAndSettle();
    expect(find.byKey(const Key('user-d1')), findsNothing);
    expect(find.byKey(const Key('user-p1')), findsOneWidget);
    await t.enterText(find.byKey(const Key('user-search')), 'ali');
    await t.testTextInput.receiveAction(TextInputAction.done);
    await t.pumpAndSettle();
    expect(repo.calls.last, 'list:patient:ali');
    expect(find.byKey(const Key('user-p1')), findsNothing);
    expect(find.byKey(const Key('user-p2')), findsOneWidget);
  });

  tallTest('pages of ten', (t) async {
    repo.all = [for (var i = 0; i < 12; i++) user('p$i', 'Patient $i', UserRole.patient)];
    await t.pumpWidget(host());
    await t.pumpAndSettle();
    expect(find.text('Showing 1 to 10 of 12 entries'), findsOneWidget);
    await t.tap(find.byKey(const Key('users-next')));
    await t.pumpAndSettle();
    expect(find.text('Showing 11 to 12 of 12 entries'), findsOneWidget);
  });

  tallTest('edit a doctor: name, specialty and caseload limit', (t) async {
    await t.pumpWidget(host());
    await t.pumpAndSettle();
    await menu(t, 'd1', 'Edit');
    expect(find.text('Currently 12 assigned'), findsOneWidget);
    await t.enterText(find.byKey(const Key('edit-name')), 'Dr John Tan');
    await t.enterText(find.byKey(const Key('edit-max')), '25');
    await t.tap(find.byKey(const Key('edit-save')));
    await t.pumpAndSettle();
    expect(repo.calls, contains('update:d1:Dr John Tan:Cardiology:25:null:null'));
  });

  tallTest('a patient edit has no specialty or limit fields', (t) async {
    await t.pumpWidget(host());
    await t.pumpAndSettle();
    await menu(t, 'p1', 'Edit');
    expect(find.byKey(const Key('edit-max')), findsNothing);
    expect(find.byKey(const Key('edit-specialty')), findsNothing);
  });

  tallTest('deactivate warns about assigned patients and logs a reason', (t) async {
    await t.pumpWidget(host());
    await t.pumpAndSettle();
    await menu(t, 'd1', 'Deactivate');
    expect(find.textContaining('12 patients are assigned to this doctor'), findsOneWidget);
    await t.enterText(find.byKey(const Key('deactivate-reason')), 'Left the clinic');
    await t.tap(find.byKey(const Key('deactivate-confirm')));
    await t.pumpAndSettle();
    expect(repo.calls, contains('update:d1:null:null:null:false:Left the clinic'));
  });

  tallTest('reactivate needs no confirmation', (t) async {
    await t.pumpWidget(host());
    await t.pumpAndSettle();
    await menu(t, 'p2', 'Reactivate');
    expect(repo.calls, contains('update:p2:null:null:null:true:null'));
    expect(find.text('Ali Bakar can sign in again.'), findsOneWidget);
  });

  tallTest('UC11.1 E1: the last admin refusal is shown', (t) async {
    repo.error = ApiException('LAST_ADMIN', 'This is the only active admin account.');
    await t.pumpWidget(host());
    await t.pumpAndSettle();
    await menu(t, 'a1', 'Deactivate');
    await t.tap(find.byKey(const Key('deactivate-confirm')));
    await t.pumpAndSettle();
    expect(find.text('This is the only active admin account.'), findsOneWidget);
  });

  tallTest('Add new user opens staff provisioning', (t) async {
    await t.pumpWidget(host());
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('add-user')));
    await t.pumpAndSettle();
    expect(find.text('ADD STAFF'), findsOneWidget);
  });
}
