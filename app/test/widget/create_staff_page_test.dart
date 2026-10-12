import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hypertension/features/admin/presentation/create_staff_page.dart';
import 'package:hypertension/shared/services/api/api_client.dart';

import '../helpers/fakes.dart';

Widget page(FakeApiClient api) => harness(
  const Scaffold(body: CreateStaffPage()),
  repo: FakeAuthRepository(),
  api: api,
);

Future<void> fillForm(WidgetTester t, {String role = 'Doctor'}) async {
  await t.tap(find.text(role));
  await t.pump();
  await t.enterText(find.byKey(const Key('staff-name')), 'Dr Tan');
  await t.enterText(find.byKey(const Key('staff-new-email')), 'tan@h.my');
}

void main() {
  tallTest('FR-1.6 UC1.5 creates a doctor and confirms the email was sent', (t) async {
    final api = FakeApiClient();
    await t.pumpWidget(page(api));
    await fillForm(t);
    await t.enterText(find.byKey(const Key('staff-specialty')), 'Cardiology');
    await t.tap(find.byKey(const Key('create-staff-submit')));
    await t.pumpAndSettle();
    expect(api.lastCreateStaff, {
      'name': 'Dr Tan',
      'email': 'tan@h.my',
      'role': 'doctor',
      'specialty': 'Cardiology',
    });
    expect(find.byKey(const Key('create-staff-result')), findsOneWidget);
    expect(find.textContaining('has been emailed'), findsOneWidget);
  });

  tallTest('pharmacist has no specialty field', (t) async {
    final api = FakeApiClient();
    await t.pumpWidget(page(api));
    await fillForm(t, role: 'Pharmacist');
    expect(find.byKey(const Key('staff-specialty')), findsNothing);
    await t.tap(find.byKey(const Key('create-staff-submit')));
    await t.pumpAndSettle();
    expect(api.lastCreateStaff!['role'], 'pharmacist');
    expect(api.lastCreateStaff!['specialty'], isNull);
  });

  tallTest('UC1.5 email failure shows the setup link to copy', (t) async {
    final api = FakeApiClient()
      ..createStaffResult = {
        'uid': 's1',
        'role': 'admin',
        'emailSent': false,
        'setupLink': 'https://reset.example/abc',
      };
    await t.pumpWidget(page(api));
    await fillForm(t, role: 'Admin');
    await t.tap(find.byKey(const Key('create-staff-submit')));
    await t.pumpAndSettle();
    expect(find.text('https://reset.example/abc'), findsOneWidget);
    expect(find.text('Copy link'), findsOneWidget);
  });

  tallTest('UC1.5 E1 duplicate email shows an error', (t) async {
    final api = FakeApiClient()
      ..createStaffError = ApiException('EMAIL_ALREADY_REGISTERED', 'exists', statusCode: 409);
    await t.pumpWidget(page(api));
    await fillForm(t);
    await t.tap(find.byKey(const Key('create-staff-submit')));
    await t.pumpAndSettle();
    expect(find.text('An account with this email already exists.'), findsOneWidget);
  });

  tallTest('blocks submit with invalid input', (t) async {
    final api = FakeApiClient();
    await t.pumpWidget(page(api));
    await t.tap(find.byKey(const Key('create-staff-submit')));
    await t.pump();
    expect(find.text('Enter your full name.'), findsOneWidget);
    expect(api.lastCreateStaff, isNull);
  });
}
