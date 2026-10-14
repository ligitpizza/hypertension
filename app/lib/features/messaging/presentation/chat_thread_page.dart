import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/enums.dart';
import '../../../core/utils/bp_classifier.dart';
import '../../../shared/models/health_models.dart';
import '../../auth/state/auth_providers.dart';
import '../../dashboard/state/dashboard_providers.dart';
import '../data/messaging_repository.dart';
import '../state/messaging_providers.dart';

/// Fig 4.3.15.2 Chat Thread / 4.3.15.3 Flagged Message (FR-10.1, FR-10.3, FR-14.4;
/// UC10.1, UC10.3; NFR-2.1). Used by the patient app and the doctor portal.
class ChatThreadPage extends ConsumerStatefulWidget {
  const ChatThreadPage({super.key, required this.otherId, this.backPath, this.draft});

  /// The other participant's uid (route `:threadId` / `:patientId`).
  final String otherId;
  final String? backPath;

  /// Pre-filled text the patient can edit before sending (e.g. a refill request).
  final String? draft;

  @override
  ConsumerState<ChatThreadPage> createState() => _ChatThreadPageState();
}

class _ChatThreadPageState extends ConsumerState<ChatThreadPage> {
  late final _input = TextEditingController(text: widget.draft);
  final _scroll = ScrollController();
  bool _sending = false;
  String? _error;

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _toBottom() => WidgetsBinding.instance.addPostFrameCallback((_) {
    if (_scroll.hasClients) _scroll.jumpTo(_scroll.position.maxScrollExtent);
  });

  Future<void> _send(String me, Contact to) async {
    final text = _input.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      await ref.read(messagingRepositoryProvider).send(me: me, to: to, text: text);
      _input.clear();
      _toBottom();
    } on RecipientNotReadyException {
      setState(() => _error = '${to.name} has not set up secure messaging yet.');
    } catch (_) {
      setState(() => _error = 'Could not send the message. Please try again.');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _showCarePlan(BuildContext context, bool isDoctor) {
    if (isDoctor) {
      context.go('/doctor/patient/${widget.otherId}/care-plan');
      return;
    }
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => Consumer(
        builder: (context, ref, _) {
          final plan = ref.watch(carePlanProvider);
          return Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('My care plan', style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 8),
                plan.when(
                  loading: () => const LinearProgressIndicator(),
                  error: (_, _) => const Text('Could not load your care plan.'),
                  data: (CarePlan? p) => Text(
                    p == null || p.content.trim().isEmpty
                        ? 'Your doctor has not written a care plan yet.' // UC10.2 E1
                        : p.content,
                    key: const Key('chat-care-plan'),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final me = ref.watch(authUidProvider).value;
    final role = ref.watch(currentUserProvider).value?.role;
    final isDoctor = role == UserRole.doctor;
    final contact = ref.watch(contactProvider(widget.otherId)).value;
    if (me == null) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    final thread = ref.watch(threadProvider((me, widget.otherId)));

    // Opening the conversation marks it read on this device (D-42).
    ref.listen(threadProvider((me, widget.otherId)), (_, next) {
      final last = next.value?.lastOrNull;
      if (last != null) {
        ref.read(chatSeenStoreProvider).markSeen(me, widget.otherId, last.sentAt);
        ref.invalidate(unreadCountProvider((me, widget.otherId)));
        _toBottom();
      }
    });

    final messages = thread.value ?? const <ChatMessage>[];
    final lastFlaggedMine = messages.lastIndexWhere((m) => m.fromMe && m.isFlagged);

    return Scaffold(
      appBar: AppBar(
        leading: BackButton(
          onPressed: () => context.canPop()
              ? context.pop()
              : context.go(widget.backPath ?? (isDoctor ? '/doctor/messages' : '/chat')),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(contact?.name ?? 'Conversation'),
            if (contact?.subtitle != null)
              Text(contact!.subtitle!, style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
        actions: [
          IconButton(
            key: const Key('chat-care-plan-button'),
            tooltip: 'Care plan',
            icon: const Icon(Icons.assignment_outlined),
            onPressed: () => _showCarePlan(context, isDoctor),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: thread.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (_, _) => const Center(
                child: Text('Could not load the conversation. Check your connection.'),
              ),
              data: (list) => list.isEmpty
                  ? const Center(
                      child: Padding(
                        padding: EdgeInsets.all(24),
                        child: Text('No messages yet. Say hello!', textAlign: TextAlign.center),
                      ),
                    )
                  : ListView.builder(
                      key: const Key('chat-list'),
                      controller: _scroll,
                      padding: const EdgeInsets.all(16),
                      itemCount: list.length,
                      itemBuilder: (_, i) => Column(
                        children: [
                          _MessageBubble(
                            message: list[i],
                            showFlag: isDoctor && list[i].isFlagged && !list[i].fromMe,
                            onDismissFlag: () =>
                                ref.read(messagingRepositoryProvider).clearFlag(list[i].id),
                          ),
                          if (!isDoctor && i == lastFlaggedMine) const _FlaggedBanner(),
                        ],
                      ),
                    ),
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.lock_outline, size: 14),
                SizedBox(width: 4),
                Text('Messages are end-to-end encrypted', style: TextStyle(fontSize: 12)),
              ],
            ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                _error!,
                key: const Key('chat-error'),
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          if (contact != null && contact.publicKey == null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                '${contact.name} has not opened CareFlow yet, so secure messages cannot be '
                'sent to them for now.',
                key: const Key('chat-not-ready'),
              ),
            ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      key: const Key('chat-input'),
                      controller: _input,
                      minLines: 1,
                      maxLines: 4,
                      maxLength: 2000,
                      enabled: contact?.publicKey != null,
                      decoration: const InputDecoration(
                        hintText: 'Type a message...',
                        counterText: '',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    key: const Key('chat-send'),
                    tooltip: 'Send',
                    onPressed: contact?.publicKey == null || _sending
                        ? null
                        : () => _send(me, contact!),
                    icon: const Icon(Icons.send),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({
    required this.message,
    required this.showFlag,
    required this.onDismissFlag,
  });

  final ChatMessage message;
  final bool showFlag;
  final VoidCallback onDismissFlag;

  static String _time(DateTime t) {
    final h = t.hour % 12 == 0 ? 12 : t.hour % 12;
    return '${t.day}/${t.month} $h:${t.minute.toString().padLeft(2, '0')} '
        '${t.hour < 12 ? 'AM' : 'PM'}';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final mine = message.fromMe;
    // docs/07: own messages right in primary; the other side left in surface colour.
    final fg = mine ? scheme.onPrimary : scheme.onSurface;
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.78),
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: mine ? scheme.primary : scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(16),
          border: showFlag
              ? Border.all(color: BpClassifier.color(BpCategory.crisis), width: 2)
              : null,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (showFlag)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.flag, size: 16, color: BpClassifier.color(BpCategory.crisis)),
                  const SizedBox(width: 4),
                  const Text('Flagged: high-risk words'),
                  TextButton(
                    key: Key('dismiss-flag-${message.id}'),
                    onPressed: onDismissFlag,
                    child: const Text('Dismiss flag'),
                  ),
                ],
              ),
            if (message.text == null)
              Text(
                'This message was encrypted for an earlier device and cannot be shown here.',
                key: Key('earlier-device-${message.id}'),
                style: TextStyle(color: fg, fontStyle: FontStyle.italic),
              )
            else
              SelectableText(message.text!, style: TextStyle(color: fg)),
            const SizedBox(height: 4),
            Text(
              message.pending ? 'Sending... (will send when online)' : _time(message.sentAt),
              key: message.pending ? Key('pending-${message.id}') : null,
              style: TextStyle(color: fg.withValues(alpha: 0.7), fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }
}

/// Fig 4.3.15.3 (999, not 911 as in the mockup).
class _FlaggedBanner extends StatelessWidget {
  const _FlaggedBanner();

  @override
  Widget build(BuildContext context) {
    final red = BpClassifier.color(BpCategory.crisis);
    return Container(
      key: const Key('chat-flagged-banner'),
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: red.withValues(alpha: 0.12),
        border: Border(left: BorderSide(color: red, width: 4)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.warning_amber_rounded, color: red),
          const SizedBox(width: 8),
          const Expanded(
            child: Text(
              'This message has been flagged for urgent review. Your care team has been '
              'notified and will respond shortly. If symptoms worsen, call 999 or go to the '
              'nearest emergency department.',
            ),
          ),
        ],
      ),
    );
  }
}
