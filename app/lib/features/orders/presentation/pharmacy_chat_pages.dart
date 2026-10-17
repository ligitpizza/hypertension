import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../shared/services/api/api_client.dart';
import '../../auth/state/auth_providers.dart';
import '../../messaging/data/conversations_repository.dart';
import '../../messaging/presentation/chat_ui.dart';
import '../../messaging/presentation/conversation_pages.dart';
import '../../messaging/state/messaging_providers.dart';
import '../data/order_models.dart';
import '../state/orders_providers.dart';

/// D-69 pharmacy chat: one 'Harvey Pharmacy' conversation per patient, shared by every
/// pharmacist. Not end-to-end encrypted (order and refill updates, not clinical advice).
const pharmacyChatNote =
    'Messages with the pharmacy are about orders and refills. For medical advice, '
    'message your doctor. In an emergency call 999.';

/// The conversation itself; [forPharmacist] picks the side ("me").
class PharmacyChatView extends ConsumerStatefulWidget {
  const PharmacyChatView({super.key, this.patientId});

  /// Null for the patient's own chat; the patient's uid for a pharmacist.
  final String? patientId;

  bool get forPharmacist => patientId != null;

  /// How often an open conversation checks for new messages.
  static const refreshEvery = Duration(seconds: 8);

  @override
  ConsumerState<PharmacyChatView> createState() => _PharmacyChatViewState();
}

class _PharmacyChatViewState extends ConsumerState<PharmacyChatView> {
  final _text = TextEditingController();
  Timer? _poll;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _poll = Timer.periodic(PharmacyChatView.refreshEvery, (_) => _refresh());
  }

  @override
  void dispose() {
    _poll?.cancel();
    _text.dispose();
    super.dispose();
  }

  void _refresh() {
    final id = widget.patientId;
    if (id == null) {
      ref.invalidate(myPharmacyChatProvider);
    } else {
      ref.invalidate(pharmacyThreadProvider(id));
    }
  }

  Future<void> _send() async {
    final text = _text.text.trim();
    if (text.isEmpty) return;
    setState(() => _sending = true);
    final repo = ref.read(ordersRepositoryProvider);
    try {
      final id = widget.patientId;
      if (id == null) {
        await repo.sendToPharmacy(text);
      } else {
        await repo.sendToPatient(id, text);
      }
      _text.clear();
      _refresh();
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  /// D-76: opening the chat marks it read on this device.
  void _seen(List<PharmacyMessage> list) {
    final me = ref.read(authUidProvider).value;
    final last = list.lastOrNull?.sentAt;
    if (me == null || last == null) return;
    final id = widget.patientId;
    markChatSeen(ref, me, id == null ? 'pharmacy' : 'pharmacy_$id', last);
  }

  @override
  Widget build(BuildContext context) {
    final id = widget.patientId;
    final AsyncValue<List<PharmacyMessage>> messages = id == null
        ? ref.watch(myPharmacyChatProvider)
        : ref.watch(pharmacyThreadProvider(id)).whenData((t) => t.messages);
    final list = messages.value;
    if (list != null) WidgetsBinding.instance.addPostFrameCallback((_) => _seen(list));
    return Column(
      children: [
        const ChatNoteBar(pharmacyChatNote, icon: Icons.info_outline),
        Expanded(
          child: messages.when(
            skipLoadingOnRefresh: true,
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (_, _) => Center(
              child: TextButton(onPressed: _refresh, child: const Text('Could not load. Retry')),
            ),
            data: (list) => list.isEmpty
                ? Center(
                    key: const Key('pharmacy-chat-empty'),
                    child: Text(
                      widget.forPharmacist
                          ? 'No messages yet. Start with an update about their order.'
                          : 'Ask the pharmacy about your orders and refills.',
                    ),
                  )
                : ListView(
                    reverse: true,
                    padding: const EdgeInsets.all(12),
                    children: [
                      for (final m in list.reversed)
                        ChatBubble(
                          mine: widget.forPharmacist ? m.fromPharmacy : !m.fromPharmacy,
                          senderName: m.senderName,
                          senderRole: m.senderRole,
                          time: m.sentAt == null ? null : chatTime(m.sentAt!),
                          child: Text(m.text),
                        ),
                    ],
                  ),
          ),
        ),
        ChatComposer(
          controller: _text,
          onSend: _sending ? null : _send,
          inputKey: const Key('pharmacy-chat-input'),
          sendKey: const Key('pharmacy-chat-send'),
        ),
      ],
    );
  }
}

/// Patient app: the Harvey Pharmacy conversation.
class PatientPharmacyChatPage extends StatelessWidget {
  const PatientPharmacyChatPage({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Harvey Pharmacy')),
    body: const PharmacyChatView(),
  );
}

/// Staff portal: the pharmacist's inbox. Patients' Harvey Pharmacy chats (shared by all
/// pharmacists) and, since D-76, team and admin chats.
class PharmacyMessagesPage extends ConsumerWidget {
  const PharmacyMessagesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = ref.watch(authUidProvider).value;
    final list = ref.watch(pharmacyConversationsProvider);
    final team = ref.watch(myConversationsProvider).value ?? const <Conversation>[];
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        InboxHeader(
          title: 'Pharmacy messages',
          subtitle:
              'Patient chats are shared by all pharmacists. Patients see them as '
              '"Harvey Pharmacy".',
          actions: [
            IconButton(
              tooltip: 'Refresh',
              onPressed: () {
                ref.invalidate(pharmacyConversationsProvider);
                ref.invalidate(myConversationsProvider);
              },
              icon: const Icon(Icons.refresh),
            ),
            // D-70: start a conversation with any patient.
            FilledButton.icon(
              key: const Key('new-message'),
              onPressed: () async {
                final uid = await showDialog<String>(
                  context: context,
                  builder: (_) => const _PickPatientDialog(),
                );
                if (uid != null && context.mounted) context.go('/pharmacy/messages/$uid');
              },
              icon: const Icon(Icons.edit_square),
              label: const Text('Message a patient'),
            ),
            OutlinedButton.icon(
              key: const Key('message-staff'),
              onPressed: () => startChat(context, ref, '/pharmacy/messages/team'),
              icon: const Icon(Icons.groups_outlined),
              label: const Text('Message staff'),
            ),
          ],
        ),
        list.when(
          loading: () => const LinearProgressIndicator(),
          error: (_, _) => TextButton(
            onPressed: () => ref.invalidate(pharmacyConversationsProvider),
            child: const Text('Could not load messages. Retry'),
          ),
          data: (convs) => InboxSection(
            key: const Key('pharmacy-inbox-empty'),
            title: 'Patients',
            empty: 'No conversations yet.',
            children: [
              for (final c in convs)
                if (me != null) _PatientRow(me: me, conversation: c),
            ],
          ),
        ),
        InboxSection(
          title: 'Team and admin',
          empty: 'No team chats yet.',
          children: conversationTiles(context, team, me, (c) => '/pharmacy/messages/team/${c.id}'),
        ),
      ],
    );
  }
}

/// One patient's pharmacy chat; a dot when the patient wrote last and it wasn't opened here.
class _PatientRow extends ConsumerWidget {
  const _PatientRow({required this.me, required this.conversation});
  final String me;
  final PharmacyConversation conversation;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final last = conversation.last;
    final seen = ref.watch(seenAtProvider((me, 'pharmacy_${last.patientId}'))).value;
    final unread =
        !last.fromPharmacy && last.sentAt != null && (seen == null || last.sentAt!.isAfter(seen));
    return InboxTile(
      key: Key('conversation-${last.patientId}'),
      title: conversation.patientName ?? 'Patient',
      role: 'patient',
      preview: '${last.fromPharmacy ? 'You: ' : ''}${last.text}',
      time: last.sentAt == null ? null : inboxTime(last.sentAt!, DateTime.now()),
      unread: unread ? -1 : 0,
      unreadKey: Key('unread-${last.patientId}'),
      onTap: () => context.go('/pharmacy/messages/${last.patientId}'),
    );
  }
}

/// Staff portal: one patient's pharmacy conversation.
class PharmacyThreadPage extends ConsumerWidget {
  const PharmacyThreadPage({super.key, required this.patientId});
  final String patientId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final name = ref.watch(pharmacyThreadProvider(patientId)).value?.patientName;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: Row(
            children: [
              TextButton.icon(
                onPressed: () => context.go('/pharmacy/messages'),
                icon: const Icon(Icons.arrow_back),
                label: const Text('Messages'),
              ),
              const SizedBox(width: 8),
              Text(name ?? '', style: Theme.of(context).textTheme.titleLarge),
              const Spacer(),
              TextButton(
                onPressed: () => context.go('/pharmacy/patients/$patientId'),
                child: const Text('Patient details'),
              ),
            ],
          ),
        ),
        Expanded(child: PharmacyChatView(patientId: patientId)),
      ],
    );
  }
}

/// D-70: choose any patient to message.
class _PickPatientDialog extends ConsumerStatefulWidget {
  const _PickPatientDialog();

  @override
  ConsumerState<_PickPatientDialog> createState() => _PickPatientDialogState();
}

class _PickPatientDialogState extends ConsumerState<_PickPatientDialog> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final list = ref.watch(pharmacyLookupProvider(_query));
    return AlertDialog(
      title: const Text('Message a patient'),
      content: SizedBox(
        width: 420,
        height: 420,
        child: Column(
          children: [
            TextField(
              key: const Key('pick-patient-search'),
              autofocus: true,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Name, email or IC',
              ),
              onSubmitted: (v) => setState(() => _query = v.trim()),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: list.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (_, _) => const Center(child: Text('Could not load patients.')),
                data: (patients) => patients.isEmpty
                    ? const Center(child: Text('No patient matches.'))
                    : ListView(
                        children: [
                          for (final p in patients)
                            ListTile(
                              key: Key('pick-${p.id}'),
                              leading: const Icon(Icons.person_outline),
                              title: Text(p.name),
                              subtitle: Text(p.email ?? p.id),
                              onTap: () => Navigator.pop(context, p.id),
                            ),
                        ],
                      ),
              ),
            ),
          ],
        ),
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel'))],
    );
  }
}
