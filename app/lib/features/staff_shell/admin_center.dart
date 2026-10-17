import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/providers/api_providers.dart';
import '../../shared/services/api/api_client.dart';
import '../appointments/domain/appointment_text.dart' show dateLabel, timeLabel;

/// D-78 admin center: doctors and pharmacists send the admin requests and follow them up;
/// the admin answers them on the Staff requests page.

const requestCategories = {
  'account': ('Account or role change', Icons.manage_accounts_outlined),
  'leave': ('Leave or unavailability', Icons.beach_access_outlined),
  'stock': ('Stock or supplier issue', Icons.inventory_2_outlined),
  'it': ('IT problem', Icons.computer_outlined),
  'other': ('Other', Icons.help_outline),
};

const requestStatuses = {'open': 'Open', 'in_progress': 'In progress', 'done': 'Done'};

Color statusColor(String status) => switch (status) {
  'open' => Colors.orange.shade700,
  'in_progress' => Colors.blue.shade600,
  _ => Colors.green.shade600,
};

class StaffRequest {
  const StaffRequest({
    required this.id,
    required this.category,
    required this.subject,
    required this.details,
    required this.status,
    this.requesterName,
    this.requesterRole,
    this.reply,
    this.repliedBy,
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String category;
  final String subject;
  final String details;
  final String status;
  final String? requesterName;
  final String? requesterRole;
  final String? reply;
  final String? repliedBy;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  factory StaffRequest.fromApi(Map<String, dynamic> j) => StaffRequest(
    id: '${j['id']}',
    category: j['category'] as String? ?? 'other',
    subject: j['subject'] as String? ?? '',
    details: j['details'] as String? ?? '',
    status: j['status'] as String? ?? 'open',
    requesterName: j['requesterName'] as String?,
    requesterRole: j['requesterRole'] as String?,
    reply: j['reply'] as String?,
    repliedBy: j['repliedBy'] as String?,
    createdAt: DateTime.tryParse('${j['createdAt']}'),
    updatedAt: DateTime.tryParse('${j['updatedAt']}'),
  );
}

final staffRequestsProvider = FutureProvider.autoDispose<List<StaffRequest>>((ref) async {
  final j = await ref.watch(apiClientProvider).staffRequests();
  return [
    for (final r in j['requests'] as List<dynamic>? ?? const [])
      StaffRequest.fromApi(r as Map<String, dynamic>),
  ];
}, retry: (_, _) => null);

class _StatusChip extends StatelessWidget {
  const _StatusChip(this.status);
  final String status;

  @override
  Widget build(BuildContext context) {
    final c = statusColor(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: c),
      ),
      child: Text(
        requestStatuses[status] ?? status,
        style: TextStyle(color: c, fontWeight: FontWeight.w600, fontSize: 12),
      ),
    );
  }
}

String _when(DateTime? t) => t == null ? '' : '${dateLabel(t)}, ${timeLabel(t)}';

/// One request card (both sides).
class _RequestCard extends StatelessWidget {
  const _RequestCard({required this.r, this.admin = false, this.onReply});
  final StaffRequest r;
  final bool admin;
  final VoidCallback? onReply;

  @override
  Widget build(BuildContext context) {
    final (label, icon) = requestCategories[r.category] ?? requestCategories['other']!;
    final theme = Theme.of(context);
    return Card(
      key: Key('request-${r.id}'),
      child: Container(
        decoration: BoxDecoration(
          border: Border(left: BorderSide(color: statusColor(r.status), width: 5)),
        ),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Expanded(child: Text(r.subject, style: theme.textTheme.titleMedium)),
                _StatusChip(r.status),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              [
                label,
                if (admin) '${r.requesterName ?? 'Staff'} (${r.requesterRole ?? ''})',
                _when(r.createdAt),
              ].join(' · '),
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            Text(r.details),
            if (r.reply != null && r.reply!.isNotEmpty)
              Container(
                key: Key('reply-${r.id}'),
                width: double.infinity,
                margin: const EdgeInsets.only(top: 10),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primaryContainer.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Reply from ${r.repliedBy ?? 'Admin'}',
                      style: theme.textTheme.labelMedium,
                    ),
                    Text(r.reply!),
                  ],
                ),
              ),
            if (onReply != null)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  key: Key('reply-button-${r.id}'),
                  onPressed: onReply,
                  icon: const Icon(Icons.reply),
                  label: const Text('Reply / update status'),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

Widget _counts(List<StaffRequest> list) => Wrap(
  spacing: 8,
  children: [
    for (final e in requestStatuses.entries)
      Chip(
        avatar: CircleAvatar(backgroundColor: statusColor(e.key), radius: 6),
        label: Text('${e.value}: ${list.where((r) => r.status == e.key).length}'),
      ),
  ],
);

/// Doctor and pharmacist: the Admin center.
class AdminCenterPage extends ConsumerWidget {
  const AdminCenterPage({super.key});

  Future<void> _new(BuildContext context, WidgetRef ref) async {
    final sent = await showDialog<bool>(context: context, builder: (_) => const _NewRequest());
    if (sent == true) ref.invalidate(staffRequestsProvider);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final list = ref.watch(staffRequestsProvider);
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Wrap(
          spacing: 12,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text('Admin center', style: Theme.of(context).textTheme.headlineSmall),
            FilledButton.icon(
              key: const Key('new-request'),
              onPressed: () => _new(context, ref),
              icon: const Icon(Icons.add),
              label: const Text('New request'),
            ),
            IconButton(
              tooltip: 'Refresh',
              onPressed: () => ref.invalidate(staffRequestsProvider),
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        const Text(
          'Ask the admin for help: account changes, leave, stock or supplier issues, IT problems. '
          "You'll get a notification when they reply.",
        ),
        const SizedBox(height: 12),
        list.when(
          loading: () => const LinearProgressIndicator(),
          error: (_, _) => TextButton(
            onPressed: () => ref.invalidate(staffRequestsProvider),
            child: const Text('Could not load your requests. Retry'),
          ),
          data: (rs) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _counts(rs),
              const SizedBox(height: 8),
              if (rs.isEmpty)
                const Padding(
                  key: Key('requests-empty'),
                  padding: EdgeInsets.all(16),
                  child: Text('No requests yet.'),
                ),
              for (final r in rs) _RequestCard(r: r),
            ],
          ),
        ),
      ],
    );
  }
}

class _NewRequest extends ConsumerStatefulWidget {
  const _NewRequest();

  @override
  ConsumerState<_NewRequest> createState() => _NewRequestState();
}

class _NewRequestState extends ConsumerState<_NewRequest> {
  final _subject = TextEditingController();
  final _details = TextEditingController();
  String _category = 'other';
  bool _sending = false;
  String? _error;

  @override
  void dispose() {
    _subject.dispose();
    _details.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (_subject.text.trim().length < 3 || _details.text.trim().length < 3) {
      setState(() => _error = 'Add a subject and some details.');
      return;
    }
    setState(() => _sending = true);
    try {
      await ref
          .read(apiClientProvider)
          .createStaffRequest(_category, _subject.text.trim(), _details.text.trim());
      if (mounted) Navigator.pop(context, true);
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('New request to the admin'),
    content: SizedBox(
      width: 480,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          DropdownButtonFormField<String>(
            key: const Key('request-category'),
            initialValue: _category,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Category'),
            items: [
              for (final e in requestCategories.entries)
                DropdownMenuItem(value: e.key, child: Text(e.value.$1)),
            ],
            onChanged: (v) => setState(() => _category = v ?? 'other'),
          ),
          const SizedBox(height: 8),
          TextField(
            key: const Key('request-subject'),
            controller: _subject,
            maxLength: 120,
            decoration: const InputDecoration(labelText: 'Subject'),
          ),
          TextField(
            key: const Key('request-details'),
            controller: _details,
            minLines: 3,
            maxLines: 6,
            maxLength: 2000,
            decoration: const InputDecoration(labelText: 'Details'),
          ),
          if (_error != null)
            Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
        ],
      ),
    ),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
      FilledButton(
        key: const Key('request-send'),
        onPressed: _sending ? null : _send,
        child: const Text('Send'),
      ),
    ],
  );
}

/// Admin: every staff request, filter by status, reply and update.
class AdminRequestsPage extends ConsumerStatefulWidget {
  const AdminRequestsPage({super.key});

  @override
  ConsumerState<AdminRequestsPage> createState() => _AdminRequestsPageState();
}

class _AdminRequestsPageState extends ConsumerState<AdminRequestsPage> {
  String? _filter = 'open';

  Future<void> _reply(StaffRequest r) async {
    final done = await showDialog<bool>(
      context: context,
      builder: (_) => _ReplyDialog(r: r),
    );
    if (done == true) ref.invalidate(staffRequestsProvider);
  }

  @override
  Widget build(BuildContext context) {
    final list = ref.watch(staffRequestsProvider);
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Row(
          children: [
            Expanded(
              child: Text('Staff requests', style: Theme.of(context).textTheme.headlineSmall),
            ),
            IconButton(
              tooltip: 'Refresh',
              onPressed: () => ref.invalidate(staffRequestsProvider),
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        const Text('Requests from doctors and pharmacists. They are notified when you reply.'),
        const SizedBox(height: 12),
        SegmentedButton<String?>(
          key: const Key('request-filter'),
          segments: [
            const ButtonSegment(value: null, label: Text('All')),
            for (final e in requestStatuses.entries)
              ButtonSegment(value: e.key, label: Text(e.value)),
          ],
          selected: {_filter},
          onSelectionChanged: (s) => setState(() => _filter = s.first),
        ),
        const SizedBox(height: 12),
        list.when(
          loading: () => const LinearProgressIndicator(),
          error: (_, _) => TextButton(
            onPressed: () => ref.invalidate(staffRequestsProvider),
            child: const Text('Could not load requests. Retry'),
          ),
          data: (rs) {
            final shown = [
              for (final r in rs)
                if (_filter == null || r.status == _filter) r,
            ];
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _counts(rs),
                if (shown.isEmpty)
                  const Padding(padding: EdgeInsets.all(16), child: Text('Nothing here.')),
                for (final r in shown) _RequestCard(r: r, admin: true, onReply: () => _reply(r)),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _ReplyDialog extends ConsumerStatefulWidget {
  const _ReplyDialog({required this.r});
  final StaffRequest r;

  @override
  ConsumerState<_ReplyDialog> createState() => _ReplyDialogState();
}

class _ReplyDialogState extends ConsumerState<_ReplyDialog> {
  late final _reply = TextEditingController(text: widget.r.reply ?? '');
  late String _status = widget.r.status == 'open' ? 'in_progress' : widget.r.status;
  bool _saving = false;

  @override
  void dispose() {
    _reply.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final text = _reply.text.trim();
      await ref
          .read(apiClientProvider)
          .updateStaffRequest(
            widget.r.id,
            status: _status,
            reply: text.isEmpty || text == widget.r.reply ? null : text,
          );
      if (mounted) Navigator.pop(context, true);
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.r.subject),
    content: SizedBox(
      width: 480,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.r.details),
          const SizedBox(height: 12),
          SegmentedButton<String>(
            key: const Key('reply-status'),
            segments: [
              for (final e in requestStatuses.entries)
                ButtonSegment(value: e.key, label: Text(e.value)),
            ],
            selected: {_status},
            onSelectionChanged: (s) => setState(() => _status = s.first),
          ),
          const SizedBox(height: 8),
          TextField(
            key: const Key('reply-text'),
            controller: _reply,
            minLines: 2,
            maxLines: 5,
            decoration: const InputDecoration(labelText: 'Reply (optional)'),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
      FilledButton(
        key: const Key('reply-save'),
        onPressed: _saving ? null : _save,
        child: const Text('Save'),
      ),
    ],
  );
}
