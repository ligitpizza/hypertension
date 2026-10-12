import 'package:firebase_auth/firebase_auth.dart';
import 'package:get_it/get_it.dart';

import '../../shared/services/api/api_client.dart';
import '../bootstrap.dart';
import '../config/app_config.dart';

/// Service locator for singletons (get_it). Riverpod providers read from here.
final locator = GetIt.instance;

void setupLocator({required AppFlavor flavor, FirebaseAuth? auth}) {
  locator
    ..registerSingleton<AppFlavor>(flavor)
    ..registerLazySingleton<ApiClient>(
      () => ApiClient.create(baseUrl: AppConfig.apiBaseUrl, auth: auth),
    );
}
