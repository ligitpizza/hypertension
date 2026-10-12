import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/api_providers.dart';

/// Increment 0 placeholder home screen. Proves the app reaches FastAPI
/// (`GET /api/v1/health`) from each client surface. Replaced by real screens
/// from Increment 1.
class WalkingSkeletonPage extends ConsumerWidget {
  const WalkingSkeletonPage({super.key, required this.title});

  final String title;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final health = ref.watch(apiHealthProvider);
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: health.when(
            loading: () => const Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text('Contacting server…'),
              ],
            ),
            data: (body) => Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.check_circle, size: 48, semanticLabel: 'Server reachable'),
                const SizedBox(height: 16),
                Text('API status: ${body['status'] ?? 'unknown'}',
                    key: const Key('health-status')),
                if (body['version'] != null) Text('Version: ${body['version']}'),
              ],
            ),
            error: (e, _) => Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.cloud_off, size: 48, semanticLabel: 'Server unreachable'),
                const SizedBox(height: 16),
                Text('Could not reach the server.', key: const Key('health-error')),
                const SizedBox(height: 8),
                Text('$e', textAlign: TextAlign.center),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () => ref.invalidate(apiHealthProvider),
                  child: const Text('Retry'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
