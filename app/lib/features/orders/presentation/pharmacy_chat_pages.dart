import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../shared/services/api/api_client.dart';
import '../../appointments/domain/appointment_text.dart' show dateLabel, timeLabel;
import '../data/order_models.dart';
import '../state/orders_providers.dart';

/// D-69 pharmacy chat: one 'CareFlow Pharmacy' conversation per patient, shared by every
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

  @override
  Widget build(BuildContext context) {
    final id = widget.patientId;
    final AsyncValue<List<PharmacyMessage>> messages = id == null
        ? ref.watch(myPharmacyChatProvider)
        : ref.watch(pharmacyThreadProvider(id)).whenData((t) => t.messages);
    final theme = Theme.of(context);
    return Column(
      children: [
        Container(
          width: double.infinity,
          color: theme.colorScheme.surfaceContainerHighest,
          padding: const EdgeInsets.all(8),
          child: Text(pharmacyChatNote, style: theme.textTheme.bodySmall),
        ),
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
                        _Bubble(
                          message: m,
                          mine: widget.forPharmacist ? m.fromPharmacy : !m.fromPharmacy,
                        ),
                    ],
                  ),
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 8, 8),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    key: const Key('pharmacy-chat-input'),
                    controller: _text,
                    minLines: 1,
                    maxLines: 4,
                    maxLength: 2000,
                    decoration: const InputDecoration(hintText: 'Write a message', counterText: ''),
                  ),
                ),
                IconButton(
                  key: const Key('pharmacy-chat-send'),
                  tooltip: 'Send',
                  onPressed: _sending ? null : _send,
                  icon: const Icon(Icons.send),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.message, required this.mine});
  final PharmacyMessage message;
  final bool mine;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final sent = message.sentAt;
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.all(10),
        constraints: const BoxConstraints(maxWidth: 420),
        decoration: BoxDecoration(
          color: mine ? scheme.primaryContainer : scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!mine) Text(message.senderName, style: Theme.of(context).textTheme.labelSmall),
            Text(message.text),
            if (sent != null)
              Text(
                '${dateLabel(sent)}, ${timeLabel(sent)}',
                style: Theme.of(context).textTheme.labelSmall,
              ),
          ],
        ),
      ),
    );
  }
}

/// Patient app: the CareFlow Pharmacy conversation.
class PatientPharmacyChatPage extends StatelessWidget {
  const PatientPharmacyChatPage({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('CareFlow Pharmacy')),
    body: const PharmacyChatView(),
  );
}

/// Staff portal: the pharmacist's inbox (one conversation per patient).
class PharmacyMessagesPage extends ConsumerWidget {
  const PharmacyMessagesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final list = ref.watch(pharmacyConversationsProvider);
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Row(
          children: [
            Expanded(
              child: Text('Pharmacy messages', style: Theme.of(context).textTheme.headlineSmall),
            ),
            IconButton(
              tooltip: 'Refresh',
              onPressed: () => ref.invalidate(pharmacyConversationsProvider),
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        const Text(
          'Shared by all pharmacists. To start a conversation, open a patient from the queue '
          'or the patient lookup.',
        ),
        const SizedBox(height: 12),
        list.when(
          loading: () => const LinearProgressIndicator(),
          error: (_, _) => TextButton(
            onPressed: () => ref.invalidate(pharmacyConversationsProvider),
            child: const Text('Could not load messages. Retry'),
          ),
          data: (convs) => convs.isEmpty
              ? const Padding(
                  key: Key('pharmacy-inbox-empty'),
                  padding: EdgeInsets.all(16),
                  child: Text('No conversations yet.'),
                )
              : Card(
                  child: Column(
                    children: [
                      for (final c in convs)
                        ListTile(
                          key: Key('conversation-${c.last.patientId}'),
                          leading: const Icon(Icons.person_outline),
                          title: Text(c.patientName ?? 'Patient'),
                          subtitle: Text(
                            '${c.last.fromPharmacy ? 'You: ' : ''}${c.last.text}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          trailing: c.last.fromPharmacy
                              ? null
                              : const Icon(Icons.mark_chat_unread_outlined),
                          onTap: () => context.go('/pharmacy/messages/${c.last.patientId}'),
                        ),
                    ],
                  ),
                ),
        ),
      ],
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
