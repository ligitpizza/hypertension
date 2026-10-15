import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../provider_portal/presentation/portal_widgets.dart';
import '../data/records_repository.dart';
import '../state/records_providers.dart';
import 'record_widgets.dart';

/// UC6.3: documents the patient has shared, on the doctor's patient page.
class SharedRecordsTab extends ConsumerWidget {
  const SharedRecordsTab({super.key, required this.patientId});

  final String patientId;

  @override
  Widget build(BuildContext context, WidgetRef ref) => AsyncSection<List<HealthRecord>>(
    value: ref.watch(sharedRecordsProvider(patientId)),
    isEmpty: (l) => l.isEmpty,
    emptyText: 'The patient has not shared any documents yet.', // E1
    builder: (list) => ListView(
      children: [
        for (final r in list)
          ListTile(
            key: Key('shared-record-${r.id}'),
            dense: true,
            leading: Icon(recordIcon(r)),
            title: Text(r.fileName),
            subtitle: Text(
              '${recordSubtitle(r)}'
              '${r.sharedAt == null ? '' : ' · shared ${formatDate(r.sharedAt!)}'}',
            ),
            trailing: Icon(r.isPdf ? Icons.download_outlined : Icons.open_in_full),
            onTap: () => openRecord(context, ref, r),
          ),
      ],
    ),
  );
}
