import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hypertension/core/constants/enums.dart';
import 'package:hypertension/features/admin/presentation/admin_user_detail_page.dart';
import 'package:hypertension/features/admin/presentation/admin_users_page.dart';
import 'package:hypertension/features/admin/state/admin_providers.dart';

import '../helpers/admin_fakes.dart';
import '../helpers/fakes.dart';

// D-61: admin detail pages for patients, doctors and pharmacists.

Map<String, dynamic> userJson(String uid, String name, String role, [Map<String, dynamic>? x]) => {
  'uid': uid,
  'name': name,
  'email': '$uid@example.com',
  'role': role,
  'isActive': true,
  'createdAt': '2026-10-01T00:00:00Z',
  ...?x,
};

late FakeAdminRepository repo;

Widget host(String initial) {
  final router = GoRouter(
    initialLocation: initial,
    routes: [
      GoRoute(
        path: '/admin/users',
        builder: (_, _) => const Scaffold(body: AdminUsersPage()),
        routes: [
          GoRoute(
            path: ':uid',
            builder: (_, s) => Scaffold(body: AdminUserDetailPage(uid: s.pathParameters['uid']!)),
          ),
        ],
      ),
    ],
  );
  return ProviderScope(
    overrides: [adminRepositoryProvider.overrideWithValue(repo)],
    child: MaterialApp.router(routerConfig: router),
  );
}

void main() {
  setUp(() {
    repo = FakeAdminRepository()
      ..details = {
        'p1': {
          'user': userJson('p1', 'Siti Aminah', 'patient'),
          'profile': {'icNumber': '900101-**-**77', 'gender': 'female', 'onboardingComplete': true},
          'patient': {
            'doctor': {'uid': 'd1', 'name': 'Dr John'},
            'latestReading': {
              'systolic': 128,
              'diastolic': 82,
              'timestamp': '2026-10-15T02:00:00Z',
            },
            'readingsLast30Days': 12,
            'risk': {'level': 'high', 'generatedAt': '2026-10-15T02:00:00Z'},
            'medications': [
              {'name': 'Losartan', 'dosage': '50mg', 'adherenceRate': 86.4},
            ],
            'appointments': [
              {
                'dateTime': '2026-10-18T02:00:00Z',
                'status': 'booked',
                'type': 'checkup',
                'bookedBy': 'admin',
                'other': 'Dr John',
              },
            ],
            'records': {'total': 3, 'shared': 1},
            'family': [
              {'uid': 'f1', 'name': 'Mum'},
            ],
          },
          'activity': [
            {'timestamp': '2026-10-15T02:00:00Z', 'action': 'LOG_VITAL_READING', 'details': 'x'},
          ],
        },
        'd1': {
          'user': userJson('d1', 'Dr John', 'doctor', {
            'specialty': 'Cardiology',
            'maxPatients': 30,
            'caseload': 2,
          }),
          'profile': <String, dynamic>{},
          'doctor': {
            'patients': [
              {'uid': 'p1', 'name': 'Siti Aminah', 'riskLevel': 'high', 'isActive': true},
              {'uid': 'p2', 'name': 'Ali', 'riskLevel': null, 'isActive': false},
            ],
            'upcoming': <Map<String, dynamic>>[],
            'completedTotal': 7,
            'openAlerts': 1,
          },
          'activity': <Map<String, dynamic>>[],
        },
        'ph': {
          'user': userJson('ph', 'Ph Tan', 'pharmacist'),
          'profile': <String, dynamic>{},
          'pharmacist': {'orders': null},
          'activity': <Map<String, dynamic>>[],
        },
      }
      ..all = [user('p1', 'Siti Aminah', UserRole.patient)];
  });

  tallTest('patient detail: profile, health, medications, appointments, family', (t) async {
    await t.pumpWidget(host('/admin/users/p1'));
    await t.pumpAndSettle();
    expect(find.text('Siti Aminah'), findsOneWidget);
    expect(find.text('900101-**-**77'), findsOneWidget);
    expect(find.text('Dr John'), findsOneWidget);
    expect(find.textContaining('128/82 mmHg'), findsOneWidget);
    expect(find.text('High'), findsOneWidget);
    expect(find.text('3 uploaded · 1 shared'), findsOneWidget);
    expect(find.text('Mum'), findsOneWidget);
    expect(find.text('Adherence 86%'), findsOneWidget);
    expect(
      find.textContaining('with Dr John · Regular checkup · booked · Admin assigned'),
      findsOneWidget,
    );
    expect(find.text('Log vital reading'), findsOneWidget);
  });

  tallTest('doctor detail: caseload, patients by risk, workload; open a patient', (t) async {
    await t.pumpWidget(host('/admin/users/d1'));
    await t.pumpAndSettle();
    expect(find.text('2 / 30 patients'), findsOneWidget);
    expect(find.text('Assigned patients (2)'), findsOneWidget);
    expect(find.text('Ali (deactivated)'), findsOneWidget);
    expect(find.text('High risk'), findsOneWidget);
    expect(find.text('7'), findsOneWidget);
    await t.tap(find.byKey(const Key('doctor-patient-p1')));
    await t.pumpAndSettle();
    expect(find.text('3 uploaded · 1 shared'), findsOneWidget);
  });

  tallTest('pharmacist detail explains orders arrive with Module 13', (t) async {
    await t.pumpWidget(host('/admin/users/ph'));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('section-pharmacist')), findsOneWidget);
    expect(find.text('No recorded activity.'), findsOneWidget);
  });

  tallTest('tapping a user in the list opens the detail page', (t) async {
    await t.pumpWidget(host('/admin/users'));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('user-p1')));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('detail-header')), findsOneWidget);
  });

  tallTest('actions from the detail page', (t) async {
    await t.pumpWidget(host('/admin/users/p1'));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('detail-toggle')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('deactivate-confirm')));
    await t.pumpAndSettle();
    expect(repo.calls, contains('update:p1:null:null:null:false:'));
  });
}
