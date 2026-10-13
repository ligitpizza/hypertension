import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../auth/state/auth_providers.dart';
import '../../provider_portal/state/portal_providers.dart';
import '../data/messaging_repository.dart';
import '../state/messaging_providers.dart';

/// Fig 4.3.15.1 Message Inbox (FR-10.1; UC10.1). Patient: their assigned doctor plus the
/// AI Health Agent (the mockup's "CareFlow Assistant").
class PatientInboxPage extends ConsumerWidget {
  const PatientInboxPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider).value;
    final doctorId = user?.assignedDoctorId;
    return Scaffold(
      appBar: AppBar(title: const Text('Messages')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (user == null)
            const Center(child: CircularProgressIndicator())
          else if (doctorId == null)
            const Card(
              key: Key('inbox-no-doctor'),
              child: ListTile(
                leading: Icon(Icons.person_off_outlined),
                title: Text('No doctor assigned yet'),
                subtitle: Text(
                  'You can message your doctor once one is assigned to you. In an emergency, '
                  'call 999.',
                ),
              ),
            )
          else
            ConversationTile(me: user.uid, otherId: doctorId, route: '/chat/$doctorId'),
          const SizedBox(height: 8),
          Card(
            child: ListTile(
              key: const Key('inbox-ai-agent'),
              leading: const CircleAvatar(child: Icon(Icons.smart_toy_outlined)),
              title: const Text('CareFlow Assistant'),
              subtitle: const Text('AI Health Agent · not a substitute for a doctor'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push('/ai-agent'),
            ),
          ),
        ],
      ),
    );
  }
}

/// Staff `/doctor/messages`: one conversation per assigned patient, latest first.
class DoctorMessagesPage extends ConsumerStatefulWidget {
  const DoctorMessagesPage({super.key});

  @override
  ConsumerState<DoctorMessagesPage> createState() => _DoctorMessagesPageState();
}

class _DoctorMessagesPageState extends ConsumerState<DoctorMessagesPage> {
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final me = ref.watch(authUidProvider).value;
    final patients = ref.watch(assignedPatientsProvider);
    final q = _search.text.trim().toLowerCase();
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('Messages', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 12),
        TextField(
          key: const Key('inbox-search'),
          controller: _search,
          onChanged: (_) => setState(() {}),
          decoration: const InputDecoration(
            prefixIcon: Icon(Icons.search),
            hintText: 'Search conversations',
            border: OutlineInputBorder(),
            isDense: true,
          ),
        ),
        const SizedBox(height: 12),
        if (me == null)
          const Center(child: CircularProgressIndicator())
        else
          patients.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (_, _) => const Text('Could not load your patients.'),
            data: (list) {
              final shown = [
                for (final p in list)
                  if (q.isEmpty || p.name.toLowerCase().contains(q)) p,
              ];
              if (shown.isEmpty) {
                return Text(
                  list.isEmpty ? 'No patients are assigned to you yet.' : 'No matches.',
                  key: const Key('inbox-empty'),
                );
              }
              return Column(
                children: [
                  for (final p in shown)
                    ConversationTile(me: me, otherId: p.uid, route: '/doctor/messages/${p.uid}'),
                ],
              );
            },
          ),
      ],
    );
  }
}

/// One inbox row: name, role, latest message preview, time and unread badge.
class ConversationTile extends ConsumerWidget {
  const ConversationTile({super.key, required this.me, required this.otherId, required this.route});

  final String me;
  final String otherId;
  final String route;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final contact = ref.watch(contactProvider(otherId)).value;
    final messages = ref.watch(threadProvider((me, otherId))).value ?? const <ChatMessage>[];
    final last = messages.lastOrNull;
    final unread = ref.watch(unreadCountProvider((me, otherId))).value ?? 0;
    final preview = last == null
        ? 'No messages yet'
        : '${last.fromMe ? 'You: ' : ''}${last.text ?? '(encrypted for an earlier device)'}';
    return Card(
      child: ListTile(
        key: Key('conversation-$otherId'),
        leading: CircleAvatar(child: Text((contact?.name ?? '?').characters.first.toUpperCase())),
        title: Row(
          children: [
            Expanded(child: Text(contact?.name ?? '...')),
            if (last?.isFlagged ?? false)
              const Padding(
                padding: EdgeInsets.only(left: 4),
                child: Icon(Icons.flag, size: 16, color: Colors.red),
              ),
          ],
        ),
        subtitle: Text(
          '${contact?.subtitle ?? ''}\n$preview',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        isThreeLine: true,
        trailing: unread == 0
            ? const Icon(Icons.chevron_right)
            : Badge(key: Key('unread-$otherId'), label: Text('$unread')),
        onTap: () => context.push(route),
      ),
    );
  }
}
