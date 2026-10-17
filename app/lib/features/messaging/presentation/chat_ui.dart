import 'package:flutter/material.dart';

import '../../appointments/domain/appointment_text.dart' show dateLabel, timeLabel;

/// D-76: one look for every conversation (doctor, pharmacy, team, assistant), taken from
/// the pharmacy chat: a note bar on top, bubbles (mine right in the primary container,
/// theirs left in grey with the sender's name and role), and a simple input row.

/// Who someone is, as a short label. Patients see the pharmacist as "Pharmacy".
String roleLabel(String? role) => switch (role) {
  'doctor' => 'Doctor',
  'pharmacist' => 'Pharmacy',
  'admin' => 'Admin',
  'patient' => 'Patient',
  'assistant' => 'Assistant',
  'agent' => 'Harvey AI',
  'system' => 'Harvey',
  _ => 'User',
};

IconData roleIcon(String? role) => switch (role) {
  'doctor' => Icons.medical_services_outlined,
  'pharmacist' => Icons.local_pharmacy_outlined,
  'admin' => Icons.admin_panel_settings_outlined,
  'assistant' || 'agent' => Icons.smart_toy_outlined,
  'system' => Icons.info_outline,
  _ => Icons.person_outline,
};

/// Each role keeps one colour everywhere, so people can tell who is who at a glance.
Color roleColor(BuildContext context, String? role) {
  final scheme = Theme.of(context).colorScheme;
  return switch (role) {
    'doctor' => Colors.blue.shade600,
    'pharmacist' => Colors.green.shade600,
    'admin' => Colors.deepPurple.shade400,
    'assistant' || 'agent' => Colors.teal.shade600,
    _ => scheme.outline,
  };
}

/// "Doctor" / "Pharmacy" / "Admin" chip.
class RoleChip extends StatelessWidget {
  const RoleChip(this.role, {super.key, this.label});

  final String? role;

  /// Overrides the default label (e.g. "Assistant").
  final String? label;

  @override
  Widget build(BuildContext context) {
    final color = roleColor(context, role);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Text(
        label ?? roleLabel(role),
        style: Theme.of(context).textTheme.labelSmall?.copyWith(color: color),
      ),
    );
  }
}

class RoleAvatar extends StatelessWidget {
  const RoleAvatar(this.role, {super.key});
  final String? role;

  @override
  Widget build(BuildContext context) {
    final color = roleColor(context, role);
    return CircleAvatar(
      backgroundColor: color.withValues(alpha: 0.15),
      foregroundColor: color,
      child: Icon(roleIcon(role)),
    );
  }
}

String chatTime(DateTime t) => '${dateLabel(t)}, ${timeLabel(t)}';

/// "10:30 AM" today, otherwise "Thu 16 Oct".
String inboxTime(DateTime t, DateTime now) {
  final a = t.toLocal();
  final b = now.toLocal();
  return a.year == b.year && a.month == b.month && a.day == b.day ? timeLabel(t) : dateLabel(t);
}

/// The grey bar at the top of a conversation.
class ChatNoteBar extends StatelessWidget {
  const ChatNoteBar(this.text, {super.key, this.icon});
  final String text;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      color: theme.colorScheme.surfaceContainerHighest,
      padding: const EdgeInsets.all(8),
      child: Row(
        children: [
          if (icon != null) ...[Icon(icon, size: 14), const SizedBox(width: 6)],
          Expanded(child: Text(text, style: theme.textTheme.bodySmall)),
        ],
      ),
    );
  }
}

/// One message bubble.
class ChatBubble extends StatelessWidget {
  const ChatBubble({
    super.key,
    required this.mine,
    required this.child,
    this.senderName,
    this.senderRole,
    this.time,
    this.highlight,
    this.header,
  });

  final bool mine;
  final Widget child;

  /// Shown above the other side's messages, with the role chip.
  final String? senderName;
  final String? senderRole;

  /// Shown under the text; null hides it.
  final String? time;

  /// Border colour for flagged messages.
  final Color? highlight;

  /// Extra row above the text (e.g. the doctor's flag controls).
  final Widget? header;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final small = Theme.of(context).textTheme.labelSmall;
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.all(10),
        constraints: BoxConstraints(
          maxWidth: (MediaQuery.sizeOf(context).width * 0.8).clamp(0, 420).toDouble(),
        ),
        decoration: BoxDecoration(
          color: mine ? scheme.primaryContainer : scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
          border: highlight == null ? null : Border.all(color: highlight!, width: 2),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!mine && (senderName != null || senderRole != null))
              Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Wrap(
                  spacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    if (senderName != null) Text(senderName!, style: small),
                    if (senderRole != null) RoleChip(senderRole),
                  ],
                ),
              ),
            ?header,
            child,
            if (time != null) Text(time!, style: small),
          ],
        ),
      ),
    );
  }
}

/// A message from Harvey AI or the system: full width, tinted, with an icon.
class ChatNotice extends StatelessWidget {
  const ChatNotice({
    super.key,
    required this.title,
    required this.text,
    this.time,
    this.urgent = false,
  });

  final String title;
  final String text;
  final String? time;
  final bool urgent;

  @override
  Widget build(BuildContext context) {
    final color = urgent ? Colors.red.shade700 : roleColor(context, 'agent');
    final small = Theme.of(context).textTheme.labelSmall;
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        border: Border(left: BorderSide(color: color, width: 4)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                urgent ? Icons.warning_amber_rounded : Icons.smart_toy_outlined,
                size: 16,
                color: color,
              ),
              const SizedBox(width: 6),
              Text(
                title,
                style: small?.copyWith(color: color, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 4),
          SelectableText(text),
          if (time != null) Text(time!, style: small),
        ],
      ),
    );
  }
}

/// The input row under every conversation.
class ChatComposer extends StatelessWidget {
  const ChatComposer({
    super.key,
    required this.controller,
    required this.onSend,
    this.enabled = true,
    this.leading,
    this.inputKey = const Key('chat-input'),
    this.sendKey = const Key('chat-send'),
    this.hint = 'Write a message',
  });

  final TextEditingController controller;

  /// Null disables the send button.
  final VoidCallback? onSend;
  final bool enabled;
  final Widget? leading;
  final Key inputKey;
  final Key sendKey;
  final String hint;

  @override
  Widget build(BuildContext context) => SafeArea(
    top: false,
    child: Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 8, 8),
      child: Row(
        children: [
          ?leading,
          Expanded(
            child: TextField(
              key: inputKey,
              controller: controller,
              enabled: enabled,
              minLines: 1,
              maxLines: 4,
              maxLength: 2000,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(hintText: hint, counterText: ''),
            ),
          ),
          IconButton(
            key: sendKey,
            tooltip: 'Send',
            onPressed: enabled ? onSend : null,
            icon: const Icon(Icons.send),
          ),
        ],
      ),
    ),
  );
}

/// One row of an inbox: avatar, name and role, latest message, time and unread badge.
class InboxTile extends StatelessWidget {
  const InboxTile({
    super.key,
    required this.title,
    required this.role,
    required this.preview,
    required this.onTap,
    this.roleText,
    this.time,
    this.unread = 0,
    this.unreadKey,
    this.flagged = false,
    this.note,
  });

  final String title;
  final String? role;
  final String? roleText;
  final String preview;
  final String? time;
  final int unread;

  /// Some sources only know "something new" (shown as a dot when unread is -1).
  final Key? unreadKey;
  final bool flagged;

  /// A second small line, e.g. "Opened by admin".
  final String? note;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bold = unread != 0;
    return ListTile(
      onTap: onTap,
      leading: RoleAvatar(role),
      title: Row(
        children: [
          Flexible(
            child: Text(
              title,
              overflow: TextOverflow.ellipsis,
              style: bold ? const TextStyle(fontWeight: FontWeight.bold) : null,
            ),
          ),
          const SizedBox(width: 6),
          RoleChip(role, label: roleText),
          if (flagged)
            const Padding(
              padding: EdgeInsets.only(left: 4),
              child: Icon(Icons.flag, size: 16, color: Colors.red),
            ),
        ],
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            preview,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: bold ? const TextStyle(fontWeight: FontWeight.w600) : null,
          ),
          if (note != null) Text(note!, style: theme.textTheme.labelSmall),
        ],
      ),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (time != null) Text(time!, style: theme.textTheme.labelSmall),
          const SizedBox(height: 4),
          if (unread > 0)
            Badge(key: unreadKey, label: Text('$unread'))
          else if (unread < 0)
            Badge(key: unreadKey, smallSize: 10)
          else
            const Icon(Icons.chevron_right, size: 18),
        ],
      ),
    );
  }
}

/// Portal inbox header, as on the pharmacy Messages page.
class InboxHeader extends StatelessWidget {
  const InboxHeader({super.key, required this.title, this.subtitle, this.actions = const []});

  final String title;
  final String? subtitle;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Wrap(
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(title, style: Theme.of(context).textTheme.headlineSmall),
          ...actions,
        ],
      ),
      if (subtitle != null) Text(subtitle!),
      const SizedBox(height: 12),
    ],
  );
}

/// A titled card of inbox rows.
class InboxSection extends StatelessWidget {
  const InboxSection({super.key, required this.title, required this.children, this.empty});

  final String title;
  final List<Widget> children;
  final String? empty;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 4),
          child: Text(title, style: Theme.of(context).textTheme.titleSmall),
        ),
        Card(
          margin: EdgeInsets.zero,
          child: children.isEmpty
              ? Padding(padding: const EdgeInsets.all(16), child: Text(empty ?? 'Nothing yet.'))
              : Column(
                  children: [
                    for (var i = 0; i < children.length; i++) ...[
                      if (i > 0) const Divider(height: 1),
                      children[i],
                    ],
                  ],
                ),
        ),
      ],
    ),
  );
}
