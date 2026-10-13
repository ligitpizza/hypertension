import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/auth/data/auth_repository.dart';
import '../features/auth/state/auth_providers.dart';
import '../features/messaging/state/messaging_providers.dart';
import 'constants/enums.dart';
import '../shared/providers/api_providers.dart';
import 'theme/app_theme.dart';
import 'theme/theme_mode.dart';

/// Root widget shared by all entrypoints; each passes its own router (NFR-3.2).
class CareFlowApp extends ConsumerWidget {
  const CareFlowApp({super.key, required this.title, required this.router});

  final String title;
  final Provider<GoRouter> router;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // D-33: register this device for alerts once a user of this app is signed in.
    ref.listen(currentUserProvider, (previous, next) {
      final user = next.value;
      if (user == null || user.uid == previous?.value?.uid) return;
      if (wrongAppMessage(user.role, ref.read(clientAppProvider)) != null) return;
      ref.read(pushServiceProvider).register();
      // D-42: make sure this device's public key is published so others can message us.
      if (user.role == UserRole.patient || user.role == UserRole.doctor) {
        ref.read(messagingRepositoryProvider).publishKey(user.uid).catchError((Object _) {});
      }
    });
    return MaterialApp.router(
      title: title,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: ref.watch(themeModeProvider),
      routerConfig: ref.watch(router),
      debugShowCheckedModeBanner: false,
    );
  }
}
