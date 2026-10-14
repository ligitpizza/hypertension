import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Lets dose reminders survive phone battery saving (D-43). Android's battery optimisation
/// can be lifted with a system dialog; brand-specific managers (Honor "App launch",
/// Xiaomi "Autostart") can only be opened for the patient, never changed by an app.
abstract interface class BackgroundAccess {
  /// True when the app is exempt from battery optimisation (or the platform has none).
  Future<bool> unrestricted();

  /// Shows Android's "Allow CareFlow to always run in the background?" dialog.
  Future<void> request();

  /// Opens CareFlow's page in the phone's settings (for the brand-specific switches).
  Future<void> openSettings();

  /// The patient chose "Not now" on this phone.
  Future<bool> dismissed();

  Future<void> dismiss();
}

class NoopBackgroundAccess implements BackgroundAccess {
  const NoopBackgroundAccess();

  @override
  Future<bool> unrestricted() async => true;

  @override
  Future<void> request() async {}

  @override
  Future<void> openSettings() async {}

  @override
  Future<bool> dismissed() async => true;

  @override
  Future<void> dismiss() async {}
}

class AndroidBackgroundAccess implements BackgroundAccess {
  const AndroidBackgroundAccess();

  static const _dismissedKey = 'careflow_background_prompt_dismissed';

  @override
  Future<bool> unrestricted() => Permission.ignoreBatteryOptimizations.isGranted;

  @override
  Future<void> request() => Permission.ignoreBatteryOptimizations.request();

  @override
  Future<void> openSettings() => openAppSettings();

  @override
  Future<bool> dismissed() async =>
      (await SharedPreferences.getInstance()).getBool(_dismissedKey) ?? false;

  @override
  Future<void> dismiss() async =>
      (await SharedPreferences.getInstance()).setBool(_dismissedKey, true);
}
