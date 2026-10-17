import 'package:flutter_test/flutter_test.dart';
import 'package:hypertension/core/constants/enums.dart';
import 'package:hypertension/core/router/routers.dart';
import 'package:hypertension/core/utils/validators.dart';
import 'package:hypertension/features/auth/data/auth_repository.dart';
import 'package:hypertension/features/auth/domain/app_user.dart';
import 'package:hypertension/features/auth/domain/onboarding_data.dart';
import 'package:hypertension/features/auth/state/auth_redirect.dart';

AppUser user({UserRole role = UserRole.patient, bool active = true, bool? onboarded = true}) =>
    AppUser(
      uid: 'u1',
      email: 'a@b.my',
      name: 'A',
      role: role,
      isActive: active,
      onboardingComplete: role == UserRole.patient ? onboarded : null,
    );

String? redirect({
  String location = '/dashboard',
  ClientApp app = ClientApp.patient,
  bool authLoading = false,
  String? uid = 'u1',
  bool profileLoading = false,
  AppUser? profile,
  bool busy = false,
}) => authRedirect(
  location: location,
  app: app,
  authLoading: authLoading,
  uid: uid,
  profileLoading: profileLoading,
  profile: profile,
  busy: busy,
  home: '/dashboard',
);

void main() {
  group('UC1.1 E2 / UC1.2 validators', () {
    test('FR-1.1 password needs 8+ chars with a letter and a digit', () {
      expect(Validators.password('abc12345'), isNull);
      expect(Validators.password('abcdefgh'), Validators.passwordRule);
      expect(Validators.password('12345678'), Validators.passwordRule);
      expect(Validators.password('ab1'), Validators.passwordRule);
    });

    test('email, phone and number range', () {
      expect(Validators.email('x@y.my'), isNull);
      expect(Validators.email('nope'), isNotNull);
      expect(Validators.email(''), isNotNull);
      expect(Validators.phone('+60 12-345 6789'), isNull);
      expect(Validators.phone('abc'), isNotNull);
      expect(Validators.numberInRange('170', 100, 250, label: 'Height'), isNull);
      expect(Validators.numberInRange('40', 100, 250, label: 'Height'), contains('between'));
      expect(Validators.numberInRange('', 100, 250, label: 'Height'), contains('required'));
    });
  });

  group('D-28 minimum age 13', () {
    final now = DateTime(2026, 10, 13);
    test('latest allowed date of birth is exactly 13 years ago', () {
      expect(Validators.latestAllowedDob(now), DateTime(2013, 10, 13));
    });
    test('age counts whole years and respects the birthday', () {
      expect(Validators.ageOn(DateTime(2013, 10, 13), now), 13);
      expect(Validators.ageOn(DateTime(2013, 10, 14), now), 12);
      expect(Validators.ageOn(DateTime(1968, 4, 12), now), 58);
    });
    test('under-13 and missing dates are rejected', () {
      expect(Validators.dateOfBirth(DateTime(2013, 10, 13), now), isNull);
      expect(Validators.dateOfBirth(DateTime(2014, 1, 1), now), contains('at least 13'));
      expect(Validators.dateOfBirth(null, now), 'Date of birth is required.');
    });
  });

  group('FR-1.3 auth redirect guard', () {
    test('signed out users can only see public routes', () {
      expect(redirect(uid: null), '/login');
      expect(redirect(uid: null, location: '/login'), isNull);
      expect(redirect(uid: null, location: '/register'), isNull);
      expect(redirect(uid: null, location: '/forgot-password'), isNull);
    });

    test('loading states go to splash', () {
      expect(redirect(authLoading: true), '/splash');
      expect(redirect(profileLoading: true), '/splash');
      expect(redirect(authLoading: true, location: '/splash'), isNull);
    });

    test('busy sign-in is never interrupted', () {
      expect(redirect(busy: true, uid: null, location: '/login'), isNull);
    });

    test('UC1.1 missing profile goes to finish-registration', () {
      expect(redirect(profile: null), '/finish-registration');
    });

    test('UC1.2 E2 deactivated account is blocked', () {
      expect(redirect(profile: user(active: false)), '/deactivated');
    });

    test('D-26 / NFR-3.2 role must match the app', () {
      // D-63: the Harvey app serves family members too; staff still cannot use it.
      expect(redirect(profile: user(role: UserRole.familyMember)), isNot('/wrong-app'));
      expect(redirect(profile: user(role: UserRole.doctor)), '/wrong-app');
      expect(redirect(app: ClientApp.staff, profile: user()), '/wrong-app');
      expect(
        redirect(
          app: ClientApp.family,
          profile: user(role: UserRole.familyMember),
        ),
        isNull,
      );
    });

    test('FR-1.4 patients must onboard first', () {
      expect(redirect(profile: user(onboarded: false)), '/onboard');
      expect(redirect(profile: user(onboarded: false), location: '/onboard'), isNull);
    });

    test('onboarded patient on an entry route goes home', () {
      for (final loc in ['/login', '/splash', '/onboard', '/register']) {
        expect(
          redirect(profile: user(), location: loc),
          '/dashboard',
          reason: loc,
        );
      }
      expect(redirect(profile: user(), location: '/onboard/complete'), isNull);
      expect(redirect(profile: user()), isNull);
    });
  });

  group('D-26 wrong-app messages', () {
    test('each app accepts only its roles', () {
      expect(wrongAppMessage(UserRole.patient, ClientApp.patient), isNull);
      expect(wrongAppMessage(UserRole.familyMember, ClientApp.patient), isNull); // D-63
      expect(wrongAppMessage(UserRole.patient, ClientApp.family), AuthMessages.usePatientApp);
      expect(wrongAppMessage(UserRole.doctor, ClientApp.patient), AuthMessages.useStaffPortal);
      for (final r in [UserRole.doctor, UserRole.pharmacist, UserRole.admin]) {
        expect(wrongAppMessage(r, ClientApp.staff), isNull);
      }
      expect(wrongAppMessage(UserRole.patient, ClientApp.staff), AuthMessages.usePatientApp);
      expect(wrongAppMessage(null, ClientApp.staff), AuthMessages.generic);
    });
  });

  group('UC1.2 E1/E2 Firebase error mapping', () {
    test('wrong email or password gives one generic message', () {
      for (final code in ['invalid-credential', 'wrong-password', 'user-not-found']) {
        final f = mapFirebaseSignInError(code);
        expect(f.reason, LoginFailureReason.invalidCredentials);
        expect(f.message, AuthMessages.invalidCredentials);
      }
    });

    test('disabled account shows contact-support message', () {
      final f = mapFirebaseSignInError('user-disabled');
      expect(f.reason, LoginFailureReason.accountDeactivated);
      expect(f.message, contains('contact support'));
    });

    test('rate limiting and unknown errors', () {
      expect(
        mapFirebaseSignInError('too-many-requests').reason,
        LoginFailureReason.tooManyAttempts,
      );
      expect(mapFirebaseSignInError('weird').message, AuthMessages.generic);
    });
  });

  group('FR-1.3 staff role guard', () {
    test('staff can only open their own section', () {
      // D-77: each role lands on its dashboard.
      expect(staffRoleGuard('/admin/users', UserRole.doctor), '/doctor/dashboard');
      expect(staffRoleGuard('/doctor', UserRole.pharmacist), '/pharmacy/dashboard');
      expect(staffRoleGuard('/pharmacy', UserRole.admin), '/admin/dashboard');
      expect(staffRoleGuard('/admin/users', UserRole.admin), isNull);
      expect(staffRoleGuard('/doctor', UserRole.doctor), isNull);
      expect(staffRoleGuard('/login', UserRole.doctor), isNull);
    });
  });

  group('FR-1.4 / D-25 onboarding payload', () {
    OnboardingData filled() => OnboardingData()
      ..dateOfBirth = DateTime(1968, 4, 2)
      ..gender = Gender.female
      ..heightCm = 160
      ..weightKg = 70.5
      ..phone = ' 0123456789 '
      ..conditions = {MedicalCondition.diabetes}
      ..familyHistory = {FamilyHistoryCondition.stroke}
      ..smokingStatus = SmokingStatus.never
      ..alcohol = AlcoholUse.none
      ..exerciseDaysPerWeek = 3
      ..saltIntake = SaltIntake.moderate;

    test('API JSON matches the D-25 shape', () {
      final json = filled().toApiJson();
      expect(json['dateOfBirth'], '1968-04-02');
      expect(json['gender'], 'female');
      final personal = json['personalInfo'] as Map;
      expect(personal['phone'], '0123456789');
      expect(personal.containsKey('emergencyContact'), isFalse);
      expect((json['medicalHistory'] as Map)['conditions'], ['diabetes']);
      expect((json['lifestyleFactors'] as Map)['saltIntake'], 'moderate');
    });

    test('emergency contact is included once any field is filled', () {
      final json =
          (filled()
                ..emergencyName = 'Siti'
                ..emergencyPhone = '0123456789'
                ..emergencyRelationship = 'Sister')
              .toApiJson();
      expect((json['personalInfo'] as Map)['emergencyContact'], {
        'name': 'Siti',
        'phone': '0123456789',
        'relationship': 'Sister',
      });
    });

    test('UC1.4 A1 draft round-trips through JSON', () {
      final restored = OnboardingData.fromDraftJson(filled().toDraftJson());
      expect(restored.toApiJson(), filled().toApiJson());
      expect(OnboardingData.fromDraftJson({}).gender, isNull);
    });
  });
}
