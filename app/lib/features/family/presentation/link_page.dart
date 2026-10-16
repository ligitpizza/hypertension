import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/services/api/api_client.dart';
import '../state/family_providers.dart';

/// Link to Patient (Fig 4.3.16.1; UC15.1, D-06): enter the code, wait for approval;
/// once linked, shows who you follow with Unlink (D-62).
class LinkPage extends ConsumerStatefulWidget {
  const LinkPage({super.key});

  @override
  ConsumerState<LinkPage> createState() => _LinkPageState();
}

class _LinkPageState extends ConsumerState<LinkPage> {
  final _code = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action, String done) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final messenger = ScaffoldMessenger.of(context);
    try {
      await action();
      messenger.showSnackBar(SnackBar(content: Text(done)));
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } catch (_) {
      setState(() => _error = 'Something went wrong. Please try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final repo = ref.read(familyRepositoryProvider);
    final linked = ref.watch(linkedPatientIdProvider).value;
    final pending = ref.watch(myPendingLinkProvider).value;
    final theme = Theme.of(context);
    Widget body;
    if (linked != null) {
      final person = ref.watch(linkedPersonProvider(linked)).value;
      body = Card(
        key: const Key('link-linked'),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('You are following', style: theme.textTheme.labelLarge),
              Text(person?.name ?? 'your family member', style: theme.textTheme.titleLarge),
              const SizedBox(height: 8),
              const Text(
                'You can see their readings and receive their emergency alerts. To follow someone '
                'else, unlink first.',
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                key: const Key('link-unlink'),
                onPressed: _busy
                    ? null
                    : () async {
                        final ok = await showDialog<bool>(
                          context: context,
                          builder: (c) => AlertDialog(
                            title: const Text('Stop following?'),
                            content: const Text(
                              'You will no longer see their readings or get their emergency alerts.',
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.of(c).pop(false),
                                child: const Text('Back'),
                              ),
                              FilledButton(
                                key: const Key('unlink-confirm'),
                                onPressed: () => Navigator.of(c).pop(true),
                                child: const Text('Unlink'),
                              ),
                            ],
                          ),
                        );
                        if (ok == true) await _run(repo.unlink, 'Unlinked.');
                      },
                icon: const Icon(Icons.link_off),
                label: const Text('Unlink'),
              ),
            ],
          ),
        ),
      );
    } else if (pending != null) {
      body = Card(
        key: const Key('link-pending'),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(Icons.hourglass_top),
                  SizedBox(width: 8),
                  Expanded(child: Text('Request sent, waiting for approval')),
                ],
              ),
              const SizedBox(height: 8),
              const Text(
                'Your family member must approve the link from their own Harvey app before you '
                'can view their data.',
              ),
              TextButton(
                key: const Key('link-withdraw'),
                onPressed: _busy
                    ? null
                    : () => _run(() => repo.withdraw(pending.id), 'Request withdrawn.'),
                child: const Text('Withdraw request'),
              ),
            ],
          ),
        ),
      );
    } else {
      body = Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Patient link code', style: theme.textTheme.labelLarge),
              const SizedBox(height: 8),
              TextField(
                key: const Key('link-code'),
                controller: _code,
                textCapitalization: TextCapitalization.characters,
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.key),
                  hintText: 'E.G. A1B2C3',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                key: const Key('link-send'),
                onPressed: _busy
                    ? null
                    : () {
                        final code = _code.text.trim();
                        if (code.length < 4) {
                          setState(() => _error = 'Enter the code your family member shared.');
                          return;
                        }
                        _run(
                          () => ref.read(familyRepositoryProvider).requestLink(code),
                          'Request sent.',
                        );
                      },
                icon: const Icon(Icons.send),
                label: const Text('Send request'),
              ),
            ],
          ),
        ),
      );
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Family Patients')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Center(
            child: CircleAvatar(
              radius: 32,
              backgroundColor: theme.colorScheme.primary,
              child: Icon(Icons.monitor_heart, color: theme.colorScheme.onPrimary, size: 32),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Link to Patient',
            textAlign: TextAlign.center,
            style: theme.textTheme.headlineSmall,
          ),
          const SizedBox(height: 4),
          const Text(
            'Enter the unique link code provided by your family member to securely monitor '
            'their health remotely.',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          body,
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                _error!,
                key: const Key('link-error'),
                style: TextStyle(color: theme.colorScheme.error),
              ),
            ),
          const SizedBox(height: 16),
          const Card(
            child: ListTile(
              leading: Icon(Icons.info_outline),
              title: Text(
                'Once requested, the patient must approve the link from their own Harvey app '
                'before you can view their data.',
              ),
            ),
          ),
        ],
      ),
    );
  }
}
