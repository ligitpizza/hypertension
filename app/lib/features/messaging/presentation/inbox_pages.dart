import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../ai_agent/data/agent_repository.dart';
import '../../ai_agent/state/agent_providers.dart';
import '../../auth/state/auth_providers.dart';
import '../../orders/data/order_models.dart';
import '../../orders/state/orders_providers.dart';
import '../../provider_portal/state/portal_providers.dart';
import '../data/conversations_repository.dart';
import '../data/messaging_repository.dart';
import '../state/messaging_providers.dart';
import 'chat_ui.dart';
import 'conversation_pages.dart';

/// Fig 4.3.15.1 Message Inbox (FR-10.1; UC10.1), redesigned in D-76: every chat shows
/// who it is with (Doctor / Pharmacy / Admin / Assistant), the latest message, the time
/// and an unread count. Patient: their doctor, the Harvey Pharmacy, chats opened with
/// them, and the Harvey Assistant (AI Health Agent and weekly summary).
class PatientInboxPage extends ConsumerWidget {
  const PatientInboxPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider).value;
    final doctorId = user?.assignedDoctorId;
    // D-76: makes sure this week's summary is waiting in the Assistant chat.
    ref.watch(weeklySummaryRequestProvider);
    final team = ref.watch(myConversationsProvider).value ?? const <Conversation>[];
    return Scaffold(
      appBar: AppBar(
        title: const Text('Messages'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: () {
              ref.invalidate(myConversationsProvider);
              ref.invalidate(myPharmacyChatProvider);
            },
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: user == null
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: () async {
                ref.invalidate(myConversationsProvider);
                ref.invalidate(myPharmacyChatProvider);
              },
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  InboxSection(
                    title: 'Your care team',
                    children: [
                      if (doctorId == null)
                        const ListTile(
                          key: Key('inbox-no-doctor'),
                          leading: RoleAvatar('doctor'),
                          title: Text('No doctor assigned yet'),
                          subtitle: Text(
                            'You can message your doctor once one is assigned to you. In an '
                            'emergency, call 999.',
                          ),
                        )
                      else
                        ConversationTile(
                          me: user.uid,
                          otherId: doctorId,
                          role: 'doctor',
                          route: '/chat/$doctorId',
                        ),
                      _PharmacyTile(me: user.uid),
                      ...conversationTiles(
                        context,
                        team,
                        user.uid,
                        (c) => '/conversation/${c.id}',
                        patientApp: true,
                      ),
                    ],
                  ),
                  InboxSection(
                    title: 'Assistant',
                    children: [_AssistantTile(me: user.uid)],
                  ),
                  Text(
                    'Messages are not for emergencies. If you feel very unwell, call 999.',
                    style: Theme.of(context).textTheme.bodySmall,
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
    );
  }
}

/// D-69 Harvey Pharmacy row; unread = pharmacy replies since it was last opened here.
class _PharmacyTile extends ConsumerWidget {
  const _PharmacyTile({required this.me});
  final String me;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final messages = ref.watch(myPharmacyChatProvider).value ?? const <PharmacyMessage>[];
    final seen = ref.watch(seenAtProvider((me, 'pharmacy'))).value;
    final last = messages.lastOrNull;
    final unread = messages
        .where(
          (m) => m.fromPharmacy && m.sentAt != null && (seen == null || m.sentAt!.isAfter(seen)),
        )
        .length;
    return InboxTile(
      key: const Key('inbox-pharmacy'),
      title: 'Harvey Pharmacy',
      role: 'pharmacist',
      preview: last == null
          ? 'Orders, refills and deliveries'
          : '${last.fromPharmacy ? '' : 'You: '}${last.text}',
      time: last?.sentAt == null ? null : inboxTime(last!.sentAt!, DateTime.now()),
      unread: unread,
      unreadKey: const Key('unread-pharmacy'),
      onTap: () => context.push('/pharmacy-chat'),
    );
  }
}

/// Harvey Assistant row: the AI Health Agent chat, where weekly summaries also arrive.
class _AssistantTile extends ConsumerWidget {
  const _AssistantTile({required this.me});
  final String me;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final messages = ref.watch(agentMessagesProvider).value ?? const <AgentMessage>[];
    final seen = ref.watch(seenAtProvider((me, 'assistant'))).value;
    final last = messages.lastOrNull;
    final unread = messages
        .where(
          (m) => !m.fromPatient && m.sentAt != null && (seen == null || m.sentAt!.isAfter(seen)),
        )
        .length;
    final preview = last == null
        ? 'AI Health Agent · not a substitute for a doctor'
        : last.kind == 'weekly_summary'
        ? 'Your weekly health summary is ready'
        : '${last.fromPatient ? 'You: ' : ''}${last.text}';
    return InboxTile(
      key: const Key('inbox-ai-agent'),
      title: 'Harvey Assistant',
      role: 'assistant',
      preview: preview,
      time: last?.sentAt == null ? null : inboxTime(last!.sentAt!, DateTime.now()),
      unread: unread,
      unreadKey: const Key('unread-assistant'),
      note: 'AI, not a substitute for a doctor',
      onTap: () => context.push('/ai-agent'),
    );
  }
}

/// Staff `/doctor/messages`: the secure chats with assigned patients, plus team and
/// admin chats (D-76).
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
    final team = ref.watch(myConversationsProvider);
    final q = _search.text.trim().toLowerCase();
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        InboxHeader(
          title: 'Messages',
          subtitle: 'Patient chats are end-to-end encrypted. Team chats are with staff.',
          actions: [
            IconButton(
              tooltip: 'Refresh',
              onPressed: () => ref.invalidate(myConversationsProvider),
              icon: const Icon(Icons.refresh),
            ),
            FilledButton.icon(
              key: const Key('new-message'),
              onPressed: () => startChat(context, ref, '/doctor/messages/team'),
              icon: const Icon(Icons.edit_square),
              label: const Text('Message staff'),
            ),
          ],
        ),
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
        else ...[
          patients.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (_, _) => const Text('Could not load your patients.'),
            data: (list) {
              final shown = [
                for (final p in list)
                  if (q.isEmpty || p.name.toLowerCase().contains(q)) p,
              ];
              return InboxSection(
                key: const Key('inbox-empty'),
                title: 'Patients',
                empty: list.isEmpty ? 'No patients are assigned to you yet.' : 'No matches.',
                children: [
                  for (final p in shown)
                    ConversationTile(
                      me: me,
                      otherId: p.uid,
                      role: 'patient',
                      route: '/doctor/messages/${p.uid}',
                      portal: true,
                    ),
                ],
              );
            },
          ),
          InboxSection(
            title: 'Team and admin',
            empty: 'No team chats yet.',
            children: conversationTiles(
              context,
              [
                for (final c in team.value ?? const <Conversation>[])
                  if (q.isEmpty || c.title.toLowerCase().contains(q)) c,
              ],
              me,
              (c) => '/doctor/messages/team/${c.id}',
            ),
          ),
        ],
      ],
    );
  }
}

/// One end-to-end encrypted conversation row (doctor <-> patient).
class ConversationTile extends ConsumerWidget {
  const ConversationTile({
    super.key,
    required this.me,
    required this.otherId,
    required this.route,
    this.role,
    this.portal = false,
  });

  final String me;
  final String otherId;
  final String route;

  /// The other person's role, for the label.
  final String? role;

  /// Portal rows navigate with go (inside the shell); the phone pushes.
  final bool portal;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final contact = ref.watch(contactProvider(otherId)).value;
    final messages = ref.watch(threadProvider((me, otherId))).value ?? const <ChatMessage>[];
    final last = messages.lastOrNull;
    final unread = ref.watch(unreadCountProvider((me, otherId))).value ?? 0;
    final preview = last == null
        ? 'No messages yet'
        : '${last.fromMe ? 'You: ' : ''}${last.text ?? '(encrypted for an earlier device)'}';
    return InboxTile(
      key: Key('conversation-$otherId'),
      title: contact?.name ?? '...',
      role: role,
      preview: preview,
      time: last == null ? null : inboxTime(last.sentAt, DateTime.now()),
      unread: unread,
      unreadKey: Key('unread-$otherId'),
      flagged: last?.isFlagged ?? false,
      note: role == 'doctor' ? contact?.subtitle : null,
      onTap: () => portal ? context.go(route) : context.push(route),
    );
  }
}
