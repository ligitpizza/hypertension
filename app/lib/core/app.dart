import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'theme/app_theme.dart';
import 'theme/theme_mode.dart';

/// Root widget shared by all entrypoints; each passes its own router (NFR-3.2).
class CareFlowApp extends ConsumerWidget {
  const CareFlowApp({super.key, required this.title, required this.router});

  final String title;
  final Provider<GoRouter> router;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
