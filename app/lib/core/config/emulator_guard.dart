// Web-only checks that keep a local (emulator) build from silently talking to
// the production Firebase project. No-ops on Android.
export 'emulator_guard_stub.dart' if (dart.library.js_interop) 'emulator_guard_web.dart';
