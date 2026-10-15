import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/services/api/api_client.dart';
import '../../auth/state/auth_providers.dart';
import '../state/family_providers.dart';

/// Patient: family link requests and linked members (`/family-requests`; UC15.1, D-06, D-62).
class FamilyRequestsPage extends ConsumerWidget {
  const FamilyRequestsPage({super.key});

  Future<void> _run(BuildContext context, Future<void> Function() action, String done) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await action();
      messenger.showSnackBar(SnackBar(content: Text(done)));
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      messenger.showSnackBar(const SnackBar(content: Text('Something went wrong. Try again.')));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.read(familyRepositoryProvider);
    final code = ref.watch(currentUserProvider).value?.linkCode;
    final pending = ref.watch(pendingFamilyRequestsProvider).value ?? const [];
    final linked = ref.watch(linkedFamilyProvider).value ?? const [];
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Family')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            key: const Key('family-code'),
            child: ListTile(
              leading: const Icon(Icons.key),
              title: Text(code ?? '-', style: theme.textTheme.headlineSmall),
              subtitle: const Text(
                'Share this code with a family member. They enter it in the CareFlow Family app '
                'and you approve the request here.',
              ),
              trailing: code == null
                  ? null
                  : IconButton(
                      tooltip: 'Copy',
                      icon: const Icon(Icons.copy),
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: code));
                        ScaffoldMessenger.of(
                          context,
                        ).showSnackBar(const SnackBar(content: Text('Code copied.')));
                      },
                    ),
            ),
          ),
          const SizedBox(height: 16),
          Text('Requests (${pending.length})', style: theme.textTheme.titleMedium),
          if (pending.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text('No requests waiting.'),
            ),
          for (final r in pending)
            Card(
              key: Key('family-request-${r.id}'),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${r.familyMemberName} wants to follow your health',
                      style: theme.textTheme.titleSmall,
                    ),
                    const Text(
                      'They will see your readings and risk level, and get emergency alerts with '
                      'your location.',
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          key: Key('family-reject-${r.id}'),
                          onPressed: () => _run(
                            context,
                            () => repo.decide(r.id, approve: false),
                            'Request declined.',
                          ),
                          child: const Text('Reject'),
                        ),
                        FilledButton(
                          key: Key('family-approve-${r.id}'),
                          onPressed: () => _run(
                            context,
                            () => repo.decide(r.id, approve: true),
                            '${r.familyMemberName} can now follow your health.',
                          ),
                          child: const Text('Approve'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 16),
          Text('Linked family (${linked.length})', style: theme.textTheme.titleMedium),
          if (linked.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text('Nobody follows your health yet.'),
            ),
          for (final m in linked)
            Card(
              child: ListTile(
                key: Key('family-member-${m.uid}'),
                leading: const Icon(Icons.person_outline),
                title: Text(m.name),
                subtitle: const Text('Sees your readings and emergency alerts'),
                trailing: TextButton(
                  key: Key('family-remove-${m.uid}'),
                  onPressed: () async {
                    final ok = await showDialog<bool>(
                      context: context,
                      builder: (c) => AlertDialog(
                        title: Text('Remove ${m.name}?'),
                        content: const Text(
                          'They will no longer see your readings or receive your emergency alerts.',
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.of(c).pop(false),
                            child: const Text('Back'),
                          ),
                          FilledButton(
                            key: const Key('family-remove-confirm'),
                            onPressed: () => Navigator.of(c).pop(true),
                            child: const Text('Remove'),
                          ),
                        ],
                      ),
                    );
                    if (ok == true && context.mounted) {
                      await _run(context, () => repo.removeMember(m.uid), '${m.name} was removed.');
                    }
                  },
                  child: const Text('Remove'),
                ),
              ),
            ),
          const SizedBox(height: 16),
          const _LocationSetting(),
        ],
      ),
    );
  }
}

/// D-62: location is only used in emergencies; the patient grants it here or at SOS.
class _LocationSetting extends ConsumerStatefulWidget {
  const _LocationSetting();

  @override
  ConsumerState<_LocationSetting> createState() => _LocationSettingState();
}

class _LocationSettingState extends ConsumerState<_LocationSetting> {
  bool? _granted;

  @override
  void initState() {
    super.initState();
    ref.read(locationSourceProvider).granted().then((g) {
      if (mounted) setState(() => _granted = g);
    });
  }

  @override
  Widget build(BuildContext context) => Card(
    key: const Key('family-location'),
    child: ListTile(
      leading: Icon(_granted == true ? Icons.location_on : Icons.location_off),
      title: const Text('Share my location in emergencies'),
      subtitle: Text(
        _granted == true
            ? 'On. Your location is sent only with an emergency alert to your family.'
            : 'Off. Turn on so family can find you if an emergency is detected.',
      ),
      trailing: _granted == true
          ? null
          : TextButton(
              key: const Key('family-location-allow'),
              onPressed: () async {
                final loc = await ref.read(locationSourceProvider).current(ask: true);
                if (mounted) setState(() => _granted = loc != null);
              },
              child: const Text('Allow'),
            ),
    ),
  );
}
