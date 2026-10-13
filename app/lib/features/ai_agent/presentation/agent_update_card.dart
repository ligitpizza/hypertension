import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/enums.dart';
import '../../../core/utils/risk_style.dart';
import '../data/agent_repository.dart';
import '../state/agent_providers.dart';

/// UC2.7 Receive Proactive Health Update (D-34): requested once when Reading Saved opens,
/// so saving the reading itself stays fast. Also saved to the agent chat history.
/// Quick replies when the chat is opened from a reading update.
const readingQuickReplies = [
  'What does my latest reading mean?',
  'Explain my risk score',
  'What should I do next?',
  'How can I lower my blood pressure?',
];

class AgentUpdateCard extends ConsumerStatefulWidget {
  const AgentUpdateCard({super.key});

  @override
  ConsumerState<AgentUpdateCard> createState() => _AgentUpdateCardState();
}

class _AgentUpdateCardState extends ConsumerState<AgentUpdateCard> {
  late final Future<ProactiveUpdate> _update;

  @override
  void initState() {
    super.initState();
    _update = ref.read(agentRepositoryProvider).proactive();
  }

  /// Buttons whose screens exist. Call Emergency Contact and Alert Family arrive with
  /// family monitoring (FR-14.2); until then the text tells the patient to call 999.
  static (String, IconData, String)? _button(AgentAction a) => switch (a) {
    AgentAction.bookAppointment => ('Book appointment', Icons.event_available, '/appointments'),
    AgentAction.bookEmergencyAppointment => (
      'Book emergency appointment',
      Icons.event_busy,
      '/appointments',
    ),
    AgentAction.viewMedications => ('View medications', Icons.medication_outlined, '/medications'),
    AgentAction.callEmergencyContact || AgentAction.alertFamily => null,
  };

  @override
  Widget build(BuildContext context) {
    return Card(
      key: const Key('agent-update'),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: FutureBuilder<ProactiveUpdate>(
          future: _update,
          builder: (context, snap) {
            final header = Row(
              children: [
                const Icon(Icons.smart_toy_outlined),
                const SizedBox(width: 8),
                const Expanded(child: Text('AI Health Agent')),
                if (snap.data?.riskLevel case final RiskLevel level)
                  Chip(
                    visualDensity: VisualDensity.compact,
                    avatar: CircleAvatar(backgroundColor: riskColor(level), radius: 5),
                    label: Text(riskLabel(level)),
                  ),
              ],
            );
            if (snap.connectionState != ConnectionState.done) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  header,
                  const SizedBox(height: 8),
                  const Row(
                    children: [
                      SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      SizedBox(width: 8),
                      Text('Preparing your update...'),
                    ],
                  ),
                ],
              );
            }
            if (snap.hasError) {
              // UC2.6 E1 pattern: the reading is saved; just skip the update.
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  header,
                  const SizedBox(height: 8),
                  const Text(
                    'Your update isn\'t available right now. Your reading is saved.',
                    key: Key('agent-update-error'),
                  ),
                ],
              );
            }
            final u = snap.data!;
            final buttons = [for (final a in u.actions) ?_button(a)];
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                header,
                const SizedBox(height: 8),
                Text(u.text, key: const Key('agent-update-text')),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final (label, icon, route) in buttons)
                      FilledButton.icon(
                        key: Key('agent-action-$route-$label'),
                        onPressed: () => context.push(route),
                        icon: Icon(icon),
                        label: Text(label),
                      ),
                    OutlinedButton.icon(
                      key: const Key('agent-open-chat'),
                      onPressed: () => context.push('/ai-agent', extra: readingQuickReplies),
                      icon: const Icon(Icons.chat_bubble_outline),
                      label: const Text('Ask the assistant'),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'General information, not a substitute for a doctor.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
