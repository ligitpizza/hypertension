import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/enums.dart';
import '../../features/auth/state/auth_providers.dart';
import 'confirm_sign_out.dart';

/// Temporary landing page after sign-in until the Module 2 dashboard (patient)
/// and the family dashboard (Increment 3) replace it.
class HomePlaceholder extends ConsumerWidget {
  const HomePlaceholder({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider).value;
    final app = ref.watch(clientAppProvider);
    return Scaffold(
      appBar: AppBar(
        title: Text(app == ClientApp.family ? 'CareFlow Family' : 'CareFlow'),
        actions: [
          IconButton(
            key: const Key('home-sign-out'),
            tooltip: 'Sign out',
            icon: const Icon(Icons.logout),
            onPressed: () => confirmAndSignOut(context, ref),
          ),
        ],
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Welcome, ${user?.name ?? ''}', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
              Text(
                app == ClientApp.family
                    ? 'Linking to a patient is coming soon.'
                    : 'Your dashboard is coming soon.',
                textAlign: TextAlign.center,
              ),
              if (user?.linkCode != null) ...[
                const SizedBox(height: 16),
                Text('Family link code: ${user!.linkCode}'),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
