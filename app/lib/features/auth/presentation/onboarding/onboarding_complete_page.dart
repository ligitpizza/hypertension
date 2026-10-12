import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Fig 4.3.1.2 Onboarding Complete: confirms the profile was saved, then
/// redirects to the dashboard (UC1.4 step 5).
class OnboardingCompletePage extends StatefulWidget {
  const OnboardingCompletePage({super.key, this.autoRedirect = const Duration(seconds: 3)});

  final Duration? autoRedirect;

  @override
  State<OnboardingCompletePage> createState() => _OnboardingCompletePageState();
}

class _OnboardingCompletePageState extends State<OnboardingCompletePage> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    final delay = widget.autoRedirect;
    if (delay != null) _timer = Timer(delay, _go);
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _go() {
    if (mounted) context.go('/dashboard');
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircleAvatar(
                    radius: 56,
                    backgroundColor: scheme.primaryContainer,
                    child: Icon(
                      Icons.check,
                      size: 56,
                      color: scheme.primary,
                      semanticLabel: 'Profile complete',
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text('Profile Complete', style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 8),
                  const Text(
                    'Your health profile has been successfully set up. '
                    'Redirecting you to your dashboard...',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 32),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      key: const Key('onboarding-go-dashboard'),
                      onPressed: _go,
                      child: const Text('Go to Dashboard'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
