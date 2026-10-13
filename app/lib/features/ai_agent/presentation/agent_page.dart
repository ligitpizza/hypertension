import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/enums.dart';
import '../../../core/utils/bp_classifier.dart';
import '../../../shared/services/api/api_client.dart';
import '../data/agent_repository.dart';
import '../state/agent_providers.dart';

/// Fig 4.3.7.1 AI Health Agent chat (FR-14.1; UC2.6, UC2.6 A1/E1; D-34).
class AgentPage extends ConsumerStatefulWidget {
  const AgentPage({super.key, this.quickReplies});

  /// Context-specific quick replies (e.g. from a triage result); [suggestions] otherwise.
  final List<String>? quickReplies;

  static const suggestions = [
    'What was my last blood pressure?',
    'Explain my risk score',
    'How can I lower my blood pressure?',
  ];

  @override
  ConsumerState<AgentPage> createState() => _AgentPageState();
}

class _AgentPageState extends ConsumerState<AgentPage> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  String? _pending; // patient message shown while waiting for the reply
  bool _emergency = false;
  String? _notice; // fallback / error text, not saved to the history
  String? _unsent; // the patient's message when the request failed

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _send([String? preset]) async {
    final text = (preset ?? _input.text).trim();
    if (text.isEmpty || _pending != null) return;
    _input.clear();
    setState(() {
      _pending = text;
      _notice = null;
      _unsent = null;
    });
    _scrollToEnd();
    try {
      final reply = await ref.read(agentRepositoryProvider).send(text);
      if (!mounted) return;
      setState(() {
        if (reply.emergency) _emergency = true;
        if (reply.fallback) _notice = reply.reply;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _unsent = text; // keep it on screen with a retry button
        _notice = e.code == 'TOO_MANY_REQUESTS'
            ? e.message
            : 'Sorry, I can\'t answer right now. If you need advice, contact your doctor or '
                  'care team directly. In an emergency, call 999.';
      });
    } finally {
      if (mounted) setState(() => _pending = null);
      _scrollToEnd();
    }
  }

  @override
  Widget build(BuildContext context) {
    final messages = ref.watch(agentMessagesProvider);
    final list = messages.value ?? const <AgentMessage>[];
    // Hide the optimistic bubble once the saved copy arrives from Firestore.
    final showPending =
        _pending != null &&
        !(list.isNotEmpty && list.last.fromPatient && list.last.text == _pending);

    return Scaffold(
      appBar: AppBar(
        leading: BackButton(
          onPressed: () => context.canPop() ? context.pop() : context.go('/dashboard'),
        ),
        title: const Row(
          children: [Icon(Icons.smart_toy_outlined), SizedBox(width: 8), Text('AI Health Agent')],
        ),
      ),
      body: Column(
        children: [
          const _Disclaimer(),
          Expanded(
            child: messages.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (_, _) => const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Text(
                    'Could not load your conversation. Check your connection and try again.',
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
              data: (_) => ListView(
                key: const Key('agent-list'),
                controller: _scroll,
                padding: const EdgeInsets.all(16),
                children: [
                  if (list.isEmpty && _pending == null) const _Welcome(),
                  for (final m in list) _Bubble(text: m.text, fromPatient: m.fromPatient),
                  if (showPending) _Bubble(text: _pending!, fromPatient: true),
                  if (_pending != null) const _Typing(),
                  if (_unsent != null) ...[
                    _Bubble(text: _unsent!, fromPatient: true),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton.icon(
                        key: const Key('agent-retry'),
                        onPressed: () => _send(_unsent),
                        icon: const Icon(Icons.refresh, size: 16),
                        label: const Text('Not sent. Tap to retry'),
                      ),
                    ),
                  ],
                  if (_notice != null)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Text(
                        _notice!,
                        key: const Key('agent-notice'),
                        style: TextStyle(color: Theme.of(context).colorScheme.error),
                      ),
                    ),
                  if (_emergency) const _EmergencyCard(),
                ],
              ),
            ),
          ),
          // Tap a quick reply instead of typing (mockup Fig 4.3.7.1 reply chips).
          SizedBox(
            height: 48,
            child: ListView(
              key: const Key('agent-quick-replies'),
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              children: [
                for (final q in widget.quickReplies ?? AgentPage.suggestions)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ActionChip(
                      key: Key('quick-$q'),
                      label: Text(q),
                      onPressed: _pending == null ? () => _send(q) : null,
                    ),
                  ),
              ],
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
                      key: const Key('agent-input'),
                      controller: _input,
                      minLines: 1,
                      maxLines: 4,
                      maxLength: 1000,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _send(),
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
                    key: const Key('agent-send'),
                    tooltip: 'Send',
                    onPressed: _pending == null ? _send : null,
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

/// CLAUDE.md health-safety copy: not a substitute for a doctor; emergency number 999.
class _Disclaimer extends StatelessWidget {
  const _Disclaimer();

  @override
  Widget build(BuildContext context) => Container(
    key: const Key('agent-disclaimer'),
    width: double.infinity,
    color: Theme.of(context).colorScheme.secondaryContainer,
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
    child: const Text(
      'The AI Health Agent gives general information. It is not a substitute for a doctor. '
      'In an emergency, call 999.',
      style: TextStyle(fontSize: 12),
    ),
  );
}

class _Welcome extends StatelessWidget {
  const _Welcome();

  @override
  Widget build(BuildContext context) => const _Bubble(
    text:
        'Hello! I can answer questions about your blood pressure readings, your risk '
        'assessment and healthy habits. Tap a question below or type your own.',
    fromPatient: false,
  );
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.text, required this.fromPatient});

  final String text;
  final bool fromPatient;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // docs/07: patient bubbles right in primary; agent left in surface colour.
    return Align(
      alignment: fromPatient ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.8),
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: fromPatient ? scheme.primary : scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!fromPatient)
              Text(
                'CareFlow Assistant',
                style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
              ),
            SelectableText(
              text,
              style: TextStyle(color: fromPatient ? scheme.onPrimary : scheme.onSurface),
            ),
          ],
        ),
      ),
    );
  }
}

class _Typing extends StatelessWidget {
  const _Typing();

  @override
  Widget build(BuildContext context) => const Padding(
    key: Key('agent-typing'),
    padding: EdgeInsets.symmetric(vertical: 8),
    child: Row(
      children: [
        SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
        SizedBox(width: 8),
        Text('The assistant is thinking...'),
      ],
    ),
  );
}

/// UC-14.1.3: shown after a dangerous message (the doctor has been alerted).
class _EmergencyCard extends StatelessWidget {
  const _EmergencyCard();

  @override
  Widget build(BuildContext context) => Card(
    key: const Key('agent-emergency'),
    color: BpClassifier.color(BpCategory.crisis),
    child: const Padding(
      padding: EdgeInsets.all(16),
      child: Row(
        children: [
          Icon(Icons.warning_amber_rounded, color: Colors.white),
          SizedBox(width: 12),
          Expanded(
            child: Text(
              'If this is an emergency, call 999 now. Your doctor has been notified.',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    ),
  );
}
