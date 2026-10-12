import '../../../core/constants/enums.dart';
import '../data/auth_repository.dart';
import '../domain/app_user.dart';

/// Shared auth guard for all three routers (docs/05 "Redirects").
///
/// Pure function so every branch is unit-tested. Returns the location to go to,
/// or null to stay.
String? authRedirect({
  required String location,
  required ClientApp app,
  required bool authLoading,
  required String? uid,
  required bool profileLoading,
  required AppUser? profile,
  required bool busy,
  required String home,
}) {
  const publicRoutes = {'/login', '/register', '/forgot-password'};
  final atPublic = publicRoutes.contains(location);

  // Sign-in/registration is mid-flight: let the page finish its own checks.
  if (busy) return null;
  if (authLoading) return location == '/splash' ? null : '/splash';

  if (uid == null) return atPublic ? null : '/login';

  if (profileLoading) return location == '/splash' ? null : '/splash';
  if (profile == null) {
    // Firebase account exists but register-profile hasn't completed (UC1.1 step 3).
    return location == '/finish-registration' ? null : '/finish-registration';
  }
  if (!profile.isActive) {
    return location == '/deactivated' ? null : '/deactivated'; // UC1.2 E2
  }
  if (wrongAppMessage(profile.role, app) != null) {
    return location == '/wrong-app' ? null : '/wrong-app'; // NFR-3.2, D-26
  }
  if (profile.needsOnboarding) {
    return location == '/onboard' ? null : '/onboard'; // FR-1.4
  }

  const entryRoutes = {
    '/splash',
    '/login',
    '/register',
    '/forgot-password',
    '/finish-registration',
    '/deactivated',
    '/wrong-app',
    '/onboard',
  };
  return entryRoutes.contains(location) ? home : null;
}
