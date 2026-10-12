import 'dart:js_interop';
import 'dart:js_interop_unsafe';

/// firebase_auth_web initialises Auth inside Firebase.initializeApp; a later
/// useAuthEmulator() then fails with auth/emulator-config-failed, which the
/// plugin swallows, so the app would quietly use production. The plugin connects
/// the emulator during initialisation (debug builds) when this sessionStorage key
/// is set, so set it before initializeApp.
void prepareWebAuthEmulator(String origin) {
  final storage = globalContext['sessionStorage'] as JSObject;
  storage.callMethod('setItem'.toJS, '[DEFAULT]-firebaseEmulatorOrigin'.toJS, origin.toJS);
}

/// True if the Firebase JS Auth instance is connected to an emulator.
bool? webAuthEmulatorActive() {
  final module = globalContext['firebase_auth'];
  if (module == null || module.isUndefinedOrNull) return null;
  final auth = (module as JSObject).callMethod('getAuth'.toJS) as JSObject;
  final config = auth['emulatorConfig'];
  return config != null && !config.isUndefinedOrNull;
}
