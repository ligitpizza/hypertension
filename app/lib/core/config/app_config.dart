import 'package:flutter/foundation.dart';

/// Build-time configuration passed with `--dart-define` (docs/10 §3).
/// Nothing environment-specific is hard-coded in the app.
abstract final class AppConfig {
  /// FastAPI origin, e.g. `http://10.0.2.2:8000` (Android emulator) or
  /// `http://localhost:8000` (Chrome). Empty means "same origin", which is how
  /// the deployed staff portal reaches `/api/**` through the Hosting rewrite.
  static const _apiBaseUrl = String.fromEnvironment('API_BASE_URL');

  /// When true, Firebase Auth/Firestore/Storage talk to the local Emulator Suite.
  static const useEmulators = bool.fromEnvironment('USE_EMULATORS');

  /// Host running the emulators. Defaults to `10.0.2.2` on Android (the host
  /// machine from the Android emulator) and `localhost` on web. Use
  /// `--dart-define=EMULATOR_HOST=localhost` on a physical device with `adb reverse`.
  static const _emulatorHost = String.fromEnvironment('EMULATOR_HOST');

  static String get apiBaseUrl =>
      _apiBaseUrl.isNotEmpty ? _apiBaseUrl : (kIsWeb ? Uri.base.origin : '');

  static String get emulatorHost =>
      _emulatorHost.isNotEmpty ? _emulatorHost : (kIsWeb ? 'localhost' : '10.0.2.2');

  // Ports match firebase/firebase.json "emulators".
  static const authEmulatorPort = 9099;
  static const firestoreEmulatorPort = 8080;
  static const storageEmulatorPort = 9199;
}
