import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../shared/services/api/api_client.dart';
import '../../auth/state/auth_providers.dart';
import '../data/conversations_repository.dart';
import '../state/messaging_providers.dart';
import 'chat_ui.dart';

/// D-76 team and admin-opened chats: the conversation itself, used by the patient app
/// and every portal role.
class ConversationView extends ConsumerStatefulWidget {
  const ConversationView({super.key, required this.conversationId});

  final String conversationId;

  /// How often an open conversation checks for new messages (as the pharmacy chat).
  static const refreshEvery = Duration(seconds: 8);

  @override
  ConsumerState<ConversationView> createState() => _ConversationViewState();
}

class _ConversationViewState extends ConsumerState<ConversationView> {
  final _text = TextEditingController();
  Timer? _poll;
  bool _sending = false;
  int _readCount = -1;

  @override
  void initState() {
    super.initState();
    _poll = Timer.periodic(ConversationView.refreshEvery, (_) => _refresh());
  }

  @override
  void dispose() {
    _poll?.cancel();
    _text.dispose();
    super.dispose();
  }

  void _refresh() => ref.invalidate(conversationThreadProvider(widget.conversationId));

  Future<void> _send() async {
    final text = _text.text.trim();
    if (text.isEmpty) return;
    setState(() => _sending = true);
    try {
      await ref.read(conversationsRepositoryProvider).send(widget.conversationId, text);
      _text.clear();
      _refresh();
      ref.invalidate(myConversationsProvider);
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  /// Opening (and reading) the conversation clears the unread count.
  void _markRead(ConversationThread t) {
    if (t.conversation.observer || t.messages.length == _readCount) return;
    _readCount = t.messages.length;
    unawaited(
      ref
          .read(conversationsRepositoryProvider)
          .markRead(widget.conversationId)
          .then((_) => ref.invalidate(myConversationsProvider))
          .catchError((Object _) {}),
    );
  }

  @override
  Widget build(BuildContext context) {
    final me = ref.watch(authUidProvider).value;
    final thread = ref.watch(conversationThreadProvider(widget.conversationId));
    ref.listen(conversationThreadProvider(widget.conversationId), (_, next) {
      final t = next.value;
      if (t != null) _markRead(t);
    });
    final conv = thread.value?.conversation;
    final observer = conv?.observer ?? false;
    return Column(
      children: [
        ChatNoteBar(
          observer
              ? 'You opened this chat. Only the two people in it can write here.'
              : conv?.openedByAdmin ?? false
              ? 'Chat opened by ${conv?.openedBy?.name ?? 'an admin'}. Not for emergencies: '
                    'call 999.'
              : 'Messages here are seen by Harvey staff. In an emergency call 999.',
          icon: Icons.info_outline,
        ),
        Expanded(
          child: thread.when(
            skipLoadingOnRefresh: true,
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (_, _) => Center(
              child: TextButton(onPressed: _refresh, child: const Text('Could not load. Retry')),
            ),
            data: (t) => t.messages.isEmpty
                ? const Center(
                    key: Key('conversation-empty'),
                    child: Text('No messages yet. Say hello!'),
                  )
                : ListView(
                    reverse: true,
                    padding: const EdgeInsets.all(12),
                    children: [
                      for (final m in t.messages.reversed)
                        if (m.isSystem)
                          ChatNotice(
                            key: Key('conv-msg-${m.id}'),
                            title: 'Harvey',
                            text: m.text,
                            time: m.sentAt == null ? null : chatTime(m.sentAt!),
                          )
                        else
                          ChatBubble(
                            key: Key('conv-msg-${m.id}'),
                            mine: m.senderId == me,
                            senderName: m.senderName,
                            senderRole: m.senderRole,
                            time: m.sentAt == null ? null : chatTime(m.sentAt!),
                            child: SelectableText(m.text),
                          ),
                    ],
                  ),
          ),
        ),
        if (!observer)
          ChatComposer(
            controller: _text,
            onSend: _sending ? null : _send,
            inputKey: const Key('conversation-input'),
            sendKey: const Key('conversation-send'),
          ),
      ],
    );
  }
}

/// Patient app: a chat opened with them (admin, or a pharmacist the admin assigned).
class PatientConversationPage extends ConsumerWidget {
  const PatientConversationPage({super.key, required this.conversationId});
  final String conversationId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final other = ref.watch(conversationThreadProvider(conversationId)).value?.conversation.other;
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Flexible(child: Text(other?.name ?? 'Conversation')),
            if (other != null) ...[const SizedBox(width: 8), RoleChip(other.role)],
          ],
        ),
      ),
      body: ConversationView(conversationId: conversationId),
    );
  }
}

/// Portal: a team or admin-opened chat inside the staff shell.
class StaffConversationPage extends ConsumerWidget {
  const StaffConversationPage({super.key, required this.conversationId, required this.backPath});

  final String conversationId;
  final String backPath;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final conv = ref.watch(conversationThreadProvider(conversationId)).value?.conversation;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Wrap(
            spacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              TextButton.icon(
                key: const Key('conversation-back'),
                onPressed: () => context.go(backPath),
                icon: const Icon(Icons.arrow_back),
                label: const Text('Messages'),
              ),
              Text(conv?.title ?? '', style: Theme.of(context).textTheme.titleLarge),
              if (conv?.other != null) RoleChip(conv!.other!.role),
              if (conv != null && conv.observer)
                for (final p in conv.participants) RoleChip(p.role, label: p.name),
            ],
          ),
        ),
        Expanded(child: ConversationView(conversationId: conversationId)),
      ],
    );
  }
}

/// Inbox rows for team / admin-opened chats.
List<Widget> conversationTiles(
  BuildContext context,
  List<Conversation> list,
  String? me,
  String Function(Conversation) route, {
  bool patientApp = false,
}) {
  final now = DateTime.now();
  return [
    for (final c in list)
      InboxTile(
        key: Key('team-${c.id}'),
        title: c.title,
        role: c.observer ? 'admin' : c.other?.role,
        roleText: c.observer ? 'Opened by you' : null,
        preview: c.lastText.isEmpty
            ? 'No messages yet'
            : '${c.lastSenderId == me ? 'You: ' : ''}${c.lastText}',
        time: c.lastMessageAt == null ? null : inboxTime(c.lastMessageAt!, now),
        unread: c.unread,
        unreadKey: Key('team-unread-${c.id}'),
        note: c.openedByAdmin && !c.observer && !patientApp ? 'Opened by admin' : null,
        onTap: () => patientApp ? context.push(route(c)) : context.go(route(c)),
      ),
  ];
}

/// Choose one person to message (staff: other staff; admin: anyone).
class PickPersonDialog extends ConsumerStatefulWidget {
  const PickPersonDialog({super.key, required this.title, this.exclude = const {}});

  final String title;
  final Set<String> exclude;

  @override
  ConsumerState<PickPersonDialog> createState() => _PickPersonDialogState();
}

class _PickPersonDialogState extends ConsumerState<PickPersonDialog> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final list = ref.watch(chatContactsProvider(_query));
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 440,
        height: 440,
        child: Column(
          children: [
            TextField(
              key: const Key('pick-person-search'),
              autofocus: true,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Name or email, then Enter',
              ),
              onSubmitted: (v) => setState(() => _query = v.trim()),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: list.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (_, _) => const Center(child: Text('Could not load people.')),
                data: (people) {
                  final shown = [
                    for (final p in people)
                      if (!widget.exclude.contains(p.uid)) p,
                  ];
                  return shown.isEmpty
                      ? const Center(child: Text('Nobody matches.'))
                      : ListView(
                          children: [
                            for (final p in shown)
                              ListTile(
                                key: Key('pick-person-${p.uid}'),
                                leading: RoleAvatar(p.role),
                                title: Text(p.name),
                                subtitle: Text(p.email ?? ''),
                                trailing: RoleChip(p.role),
                                onTap: () => Navigator.pop(context, p),
                              ),
                          ],
                        );
                },
              ),
            ),
          ],
        ),
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel'))],
    );
  }
}

/// Staff and admin: pick someone, start (or reopen) the chat and open it.
Future<void> startChat(BuildContext context, WidgetRef ref, String routeBase) async {
  final person = await showDialog<ChatPerson>(
    context: context,
    builder: (_) => const PickPersonDialog(title: 'New message'),
  );
  if (person == null || !context.mounted) return;
  try {
    final conv = await ref.read(conversationsRepositoryProvider).start(person.uid);
    ref.invalidate(myConversationsProvider);
    if (context.mounted) context.go('$routeBase/${conv.id}');
  } on ApiException catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }
}

/// D-76 admin: choose two people and open a chat between them.
Future<void> pairChat(BuildContext context, WidgetRef ref) async {
  final first = await showDialog<ChatPerson>(
    context: context,
    builder: (_) => const PickPersonDialog(title: 'Open a chat between… (first person)'),
  );
  if (first == null || !context.mounted) return;
  final second = await showDialog<ChatPerson>(
    context: context,
    builder: (_) =>
        PickPersonDialog(title: 'Chat between ${first.name} and…', exclude: {first.uid}),
  );
  if (second == null || !context.mounted) return;
  try {
    final conv = await ref.read(conversationsRepositoryProvider).pair(first.uid, second.uid);
    ref.invalidate(myConversationsProvider);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Chat opened between ${first.name} and ${second.name}.')),
      );
      context.go('/admin/messages/${conv.id}');
    }
  } on ApiException catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }
}

/// D-76 admin Messages page.
class AdminMessagesPage extends ConsumerWidget {
  const AdminMessagesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = ref.watch(authUidProvider).value;
    final list = ref.watch(myConversationsProvider);
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        InboxHeader(
          title: 'Messages',
          subtitle: 'Chat with anyone, or open a chat between two people.',
          actions: [
            IconButton(
              tooltip: 'Refresh',
              onPressed: () => ref.invalidate(myConversationsProvider),
              icon: const Icon(Icons.refresh),
            ),
            FilledButton.icon(
              key: const Key('new-message'),
              onPressed: () => startChat(context, ref, '/admin/messages'),
              icon: const Icon(Icons.edit_square),
              label: const Text('New message'),
            ),
            OutlinedButton.icon(
              key: const Key('pair-chat'),
              onPressed: () => pairChat(context, ref),
              icon: const Icon(Icons.connect_without_contact),
              label: const Text('Open chat between…'),
            ),
          ],
        ),
        list.when(
          loading: () => const LinearProgressIndicator(),
          error: (_, _) => TextButton(
            onPressed: () => ref.invalidate(myConversationsProvider),
            child: const Text('Could not load messages. Retry'),
          ),
          data: (all) {
            String route(Conversation c) => '/admin/messages/${c.id}';
            return Column(
              children: [
                InboxSection(
                  title: 'Your chats',
                  empty: 'No chats yet. Use New message to start one.',
                  children: conversationTiles(
                    context,
                    [
                      for (final c in all)
                        if (!c.observer) c,
                    ],
                    me,
                    route,
                  ),
                ),
                InboxSection(
                  title: 'Chats you opened for others',
                  empty: 'Use "Open chat between…" to connect two people.',
                  children: conversationTiles(
                    context,
                    [
                      for (final c in all)
                        if (c.observer) c,
                    ],
                    me,
                    route,
                  ),
                ),
              ],
            );
          },
        ),
      ],
    );
  }
}
