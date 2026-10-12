import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'theme/app_theme.dart';

/// Root widget shared by all entrypoints; each passes its own router (NFR-3.2).
class CareFlowApp extends StatelessWidget {
  const CareFlowApp({super.key, required this.title, required this.router});

  final String title;
  final GoRouter router;

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: title,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      routerConfig: router,
      debugShowCheckedModeBanner: false,
    );
  }
}
