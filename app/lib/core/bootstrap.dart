import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'config/app_config.dart';
import 'config/emulator_guard.dart';
import 'di/locator.dart';

/// Which client surface is running (D-14: one codebase, three entrypoints).
enum AppFlavor { patient, family, staff }

/// Shared start-up for every entrypoint: Firebase, emulators, DI, then the app.
Future<void> bootstrap({
  required AppFlavor flavor,
  required FirebaseOptions firebaseOptions,
  required Widget Function() app,
}) async {
  WidgetsFlutterBinding.ensureInitialized();
  if (firebaseOptions.apiKey.isEmpty) {
    throw StateError(
      'Firebase API key missing. Build with --dart-define-from-file=.env '
      '(copy app/.env.example to app/.env).',
    );
  }
  if (AppConfig.useEmulators && kIsWeb) {
    // Must happen before initializeApp, see emulator_guard_web.dart.
    prepareWebAuthEmulator('http://${AppConfig.emulatorHost}:${AppConfig.authEmulatorPort}');
  }
  await Firebase.initializeApp(options: firebaseOptions);

  if (AppConfig.useEmulators) {
    final host = AppConfig.emulatorHost;
    await FirebaseAuth.instance.useAuthEmulator(host, AppConfig.authEmulatorPort);
    FirebaseFirestore.instance.useFirestoreEmulator(host, AppConfig.firestoreEmulatorPort);
    await FirebaseStorage.instance.useStorageEmulator(host, AppConfig.storageEmulatorPort);
    // Fail closed: an emulator build must never talk to production Auth.
    if (webAuthEmulatorActive() == false) {
      throw StateError(
        'Auth emulator is not connected; refusing to use the production project. '
        'Use a debug build (F5) for local development.',
      );
    }
  }

  // NFR-4.2: offline access to previously loaded data (default on mobile; explicit on web).
  FirebaseFirestore.instance.settings = const Settings(persistenceEnabled: true);

  setupLocator(flavor: flavor, auth: FirebaseAuth.instance);
  runApp(ProviderScope(child: app()));
}
