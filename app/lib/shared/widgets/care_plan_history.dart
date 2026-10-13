import 'package:flutter/material.dart';

import '../models/health_models.dart';

/// D-41: every saved version of the care plan, newest first; the newest is the current one.
/// Used by the patient's dashboard card and the doctor's care plan editor.
class CarePlanHistoryList extends StatelessWidget {
  const CarePlanHistoryList({super.key, required this.versions, this.shrinkWrap = false});

  final List<CarePlanVersion> versions;
  final bool shrinkWrap;

  static String when(DateTime t) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    final h = t.hour % 12 == 0 ? 12 : t.hour % 12;
    return '${t.day} ${months[t.month - 1]} ${t.year}, $h:${t.minute.toString().padLeft(2, '0')} '
        '${t.hour < 12 ? 'AM' : 'PM'}';
  }

  @override
  Widget build(BuildContext context) {
    if (versions.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(8),
        child: Text('No earlier versions yet.', key: Key('care-plan-history-empty')),
      );
    }
    return ListView.separated(
      key: const Key('care-plan-history'),
      shrinkWrap: shrinkWrap,
      physics: shrinkWrap ? const NeverScrollableScrollPhysics() : null,
      itemCount: versions.length,
      separatorBuilder: (_, _) => const Divider(),
      itemBuilder: (context, i) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  when(versions[i].savedAt),
                  style: Theme.of(context).textTheme.labelMedium,
                ),
              ),
              if (i == 0) const Chip(visualDensity: VisualDensity.compact, label: Text('Current')),
            ],
          ),
          const SizedBox(height: 4),
          SelectableText(versions[i].content),
        ],
      ),
    );
  }
}
