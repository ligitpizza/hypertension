import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../../core/constants/enums.dart';
import '../../../shared/services/api/api_client.dart';
import '../../../shared/services/push/push_service.dart';
import '../domain/app_user.dart';

/// User-facing auth failure. `message` is safe to show on screen.
class AuthFailure implements Exception {
  const AuthFailure(this.reason, this.message);

  final LoginFailureReason reason;
  final String message;

  @override
  String toString() => 'AuthFailure($reason, $message)';
}

/// Module 1 auth flows (Fig 4.1.1.1). Firebase Authentication on the device is
/// the AuthNService; FastAPI creates profiles, sets role claims and audits.
abstract interface class AuthRepository {
  /// Current Firebase user id, or null when signed out.
  Stream<String?> uidChanges();

  /// Live `users/{uid}` document (null until registration finishes).
  Stream<AppUser?> watchProfile(String uid);

  /// UC1.2 + D-26: sign in, then check the selected role, the app and the account status.
  Future<AppUser> signIn({
    required String email,
    required String password,
    required UserRole selectedRole,
    required ClientApp app,
  });

  /// UC1.1: Firebase sign-up, then profile + role claim through FastAPI.
  Future<void> register({
    required String name,
    required String email,
    required String password,
    required UserRole role,
    String? icNumber,
  });

  /// UC1.2 A1.
  Future<void> sendPasswordReset(String email);

  /// UC1.4.
  Future<void> completeOnboarding(Map<String, dynamic> body);

  /// UC1.3: always clears the local session, even if the audit call fails (E1).
  Future<void> signOut(ClientApp app);
}

/// Messages shown to users (UC1.2 E1 never says which of email/password was wrong).
abstract final class AuthMessages {
  static const invalidCredentials = 'Incorrect email or password.';
  static const deactivated = 'This account has been deactivated. Please contact support.';
  static const useFamilyApp = 'Please use the CareFlow Family app.';
  static const usePatientApp = 'Please use the CareFlow app.';
  static const useStaffPortal = 'Please use the CareFlow Staff Portal.';
  static const roleMismatch = 'The selected role does not match this account.';
  static const tooManyAttempts = 'Too many attempts. Please wait a moment and try again.';
  static const emailInUse = 'This email is already registered. Please sign in instead.';
  static const weakPassword = 'Password must have at least 8 characters, a letter and a number.';
  static const network = 'Could not reach the server. Check your connection and try again.';
  static const generic = 'Something went wrong. Please try again.';
}

class FirebaseAuthRepository implements AuthRepository {
  FirebaseAuthRepository({
    required FirebaseAuth auth,
    required FirebaseFirestore firestore,
    required ApiClient api,
    PushService push = const NoopPushService(),
  }) : _auth = auth, // ignore: prefer_initializing_formals
       _db = firestore,
       _api = api, // ignore: prefer_initializing_formals
       _push = push; // ignore: prefer_initializing_formals

  final FirebaseAuth _auth;
  final FirebaseFirestore _db;
  final ApiClient _api;
  final PushService _push;

  @override
  Stream<String?> uidChanges() => _auth.authStateChanges().map((u) => u?.uid);

  @override
  Stream<AppUser?> watchProfile(String uid) => _db
      .collection(Collections.users)
      .doc(uid)
      .snapshots()
      .map((s) => s.exists ? AppUser.fromFirestore(s.id, s.data()!) : null);

  @override
  Future<AppUser> signIn({
    required String email,
    required String password,
    required UserRole selectedRole,
    required ClientApp app,
  }) async {
    final trimmed = email.trim();
    try {
      final cred = await _auth.signInWithEmailAndPassword(email: trimmed, password: password);
      final user = cred.user!;
      final token = await user.getIdTokenResult(true);
      final role = _roleFromClaims(token.claims);

      final wrongApp = wrongAppMessage(role, app);
      if (wrongApp != null) {
        throw AuthFailure(LoginFailureReason.wrongApp, wrongApp);
      }
      if (role != selectedRole) {
        throw const AuthFailure(LoginFailureReason.roleMismatch, AuthMessages.roleMismatch);
      }

      // Audits LOGIN and blocks deactivated accounts (UC1.2 E2) on the server.
      await _api.sessionEvent(event: SessionEvent.login.value, app: app.value);
      final snap = await _db.collection(Collections.users).doc(user.uid).get();
      return AppUser.fromFirestore(user.uid, snap.data()!);
    } on FirebaseAuthException catch (e) {
      final failure = mapFirebaseSignInError(e.code);
      await _reportFailure(trimmed, failure.reason, app);
      throw failure;
    } on AuthFailure catch (f) {
      await _auth.signOut();
      await _reportFailure(trimmed, f.reason, app);
      rethrow;
    } on ApiException catch (e) {
      await _auth.signOut();
      final failure = e.code == 'ACCOUNT_DEACTIVATED'
          ? const AuthFailure(LoginFailureReason.accountDeactivated, AuthMessages.deactivated)
          : const AuthFailure(LoginFailureReason.other, AuthMessages.network);
      if (failure.reason == LoginFailureReason.accountDeactivated) {
        await _reportFailure(trimmed, failure.reason, app);
      }
      throw failure;
    }
  }

  @override
  Future<void> register({
    required String name,
    required String email,
    required String password,
    required UserRole role,
    String? icNumber,
  }) async {
    UserCredential? created;
    try {
      final cred = await _auth.createUserWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
      created = cred;
      await cred.user!.updateDisplayName(name.trim());
      await _api.registerProfile(name: name.trim(), role: role.value, icNumber: icNumber);
      // Pick up the new role claim set by the server.
      await cred.user!.getIdToken(true);
    } on FirebaseAuthException catch (e) {
      throw switch (e.code) {
        'email-already-in-use' => const AuthFailure(
          LoginFailureReason.other,
          AuthMessages.emailInUse,
        ),
        'weak-password' => const AuthFailure(LoginFailureReason.other, AuthMessages.weakPassword),
        'invalid-email' => const AuthFailure(
          LoginFailureReason.other,
          'Enter a valid email address.',
        ),
        'network-request-failed' => const AuthFailure(
          LoginFailureReason.other,
          AuthMessages.network,
        ),
        _ => const AuthFailure(LoginFailureReason.other, AuthMessages.generic),
      };
    } on ApiException catch (e) {
      // D-51: a rejected IC number would leave a sign-in without a profile; remove it so
      // the person can correct the number and register again.
      if (e.code.startsWith('IC_') || e.code == 'INVALID_IC') {
        await created?.user?.delete().catchError((Object _) {});
        throw AuthFailure(LoginFailureReason.other, e.message);
      }
      // Firebase account exists but the profile call failed: the app retries
      // register-profile (idempotent) on next start via the router guard.
      throw const AuthFailure(LoginFailureReason.other, AuthMessages.network);
    }
  }

  @override
  Future<void> sendPasswordReset(String email) => _auth.sendPasswordResetEmail(email: email.trim());

  @override
  Future<void> completeOnboarding(Map<String, dynamic> body) async {
    await _api.completeOnboarding(body);
  }

  @override
  Future<void> signOut(ClientApp app) async {
    try {
      if (_auth.currentUser != null) {
        // D-33: stop this device receiving the user's alerts (needs the ID token).
        await _push.unregister().timeout(const Duration(seconds: 5)).catchError((Object _) {});
        await _api
            .sessionEvent(event: SessionEvent.logout.value, app: app.value)
            .timeout(const Duration(seconds: 5));
      }
    } catch (_) {
      // UC1.3 E1: never leave the device signed in because the audit call failed.
    } finally {
      await _auth.signOut();
    }
  }

  Future<void> _reportFailure(String email, LoginFailureReason reason, ClientApp app) async {
    try {
      await _api.reportLoginFailed(email: email, reason: reason.value, app: app.value);
    } catch (_) {
      // Best effort: auditing must not change what the user sees.
    }
  }
}

UserRole? _roleFromClaims(Map<String, dynamic>? claims) {
  final raw = claims?['role'];
  if (raw is! String) return null;
  try {
    return UserRole.fromValue(raw);
  } on ArgumentError {
    return null;
  }
}

/// D-26: each app serves specific roles. Returns the message to show, or null if allowed.
String? wrongAppMessage(UserRole? role, ClientApp app) {
  const staff = {UserRole.doctor, UserRole.pharmacist, UserRole.admin};
  switch (app) {
    case ClientApp.patient:
      // D-63: one CareFlow app for patients and family members.
      if (role == UserRole.patient || role == UserRole.familyMember) return null;
      return staff.contains(role) ? AuthMessages.useStaffPortal : AuthMessages.generic;
    case ClientApp.family:
      if (role == UserRole.familyMember) return null;
      if (role == UserRole.patient) return AuthMessages.usePatientApp;
      return staff.contains(role) ? AuthMessages.useStaffPortal : AuthMessages.generic;
    case ClientApp.staff:
      if (staff.contains(role)) return null;
      return role == UserRole.familyMember
          ? AuthMessages.useFamilyApp
          : role == UserRole.patient
          ? AuthMessages.usePatientApp
          : AuthMessages.generic;
  }
}

/// Maps Firebase sign-in error codes to user-facing failures (UC1.2 E1/E2).
AuthFailure mapFirebaseSignInError(String code) => switch (code) {
  'invalid-credential' || 'wrong-password' || 'user-not-found' || 'invalid-email' =>
    const AuthFailure(LoginFailureReason.invalidCredentials, AuthMessages.invalidCredentials),
  'user-disabled' => const AuthFailure(
    LoginFailureReason.accountDeactivated,
    AuthMessages.deactivated,
  ),
  'too-many-requests' => const AuthFailure(
    LoginFailureReason.tooManyAttempts,
    AuthMessages.tooManyAttempts,
  ),
  'network-request-failed' => const AuthFailure(LoginFailureReason.other, AuthMessages.network),
  _ => const AuthFailure(LoginFailureReason.other, AuthMessages.generic),
};
