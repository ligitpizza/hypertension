import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/admin_providers.dart';
import 'hospital_analytics_page.dart' show generateReport;

const _roles = [
  ('patient', 'Patient app', Color(0xFF0B6E99)),
  ('doctor', 'Doctors', Color(0xFF5FA8C7)),
  ('pharmacist', 'Pharmacists', Color(0xFF9CC9DD)),
  ('admin', 'Admin', Color(0xFFB0BEC5)),
  ('family_member', 'Family app', Color(0xFFCFD8DC)),
];

const _weekdays = ['MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT', 'SUN'];

/// Health & Usage Analytics (Fig 4.3.14.6; FR-11.3; D-59).
class SystemAnalyticsPage extends ConsumerStatefulWidget {
  const SystemAnalyticsPage({super.key});

  @override
  ConsumerState<SystemAnalyticsPage> createState() => _SystemAnalyticsPageState();
}

class _SystemAnalyticsPageState extends ConsumerState<SystemAnalyticsPage> {
  int _days = 7;

  @override
  Widget build(BuildContext context) {
    final data = ref.watch(systemAnalyticsProvider(_days));
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Wrap(
          spacing: 16,
          runSpacing: 12,
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Health & Usage Analytics', style: theme.textTheme.headlineSmall),
                const Text('Platform adoption, reliability and engagement.'),
              ],
            ),
            Wrap(
              spacing: 12,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                SegmentedButton<int>(
                  key: const Key('usage-days'),
                  segments: const [
                    ButtonSegment(value: 7, label: Text('7D')),
                    ButtonSegment(value: 30, label: Text('30D')),
                    ButtonSegment(value: 90, label: Text('3M')),
                  ],
                  selected: {_days},
                  onSelectionChanged: (s) => setState(() => _days = s.first),
                ),
                OutlinedButton.icon(
                  key: const Key('usage-report'),
                  onPressed: () => generateReport(context, ref),
                  icon: const Icon(Icons.download),
                  label: const Text('Export report'),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 16),
        data.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, _) => ListTile(
            leading: const Icon(Icons.cloud_off),
            title: const Text('Could not load usage analytics.'),
            trailing: TextButton(
              onPressed: () => ref.invalidate(systemAnalyticsProvider(_days)),
              child: const Text('Retry'),
            ),
          ),
          data: (s) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  _Stat(
                    'stat-clinicians',
                    'Active clinicians',
                    '${s.activeClinicians}',
                    'of ${s.totalClinicians} in the last ${s.days} days',
                    Colors.blue.shade700,
                  ),
                  _Stat(
                    'stat-uptime',
                    'System uptime',
                    s.uptime == null ? '—' : '${s.uptime!.toStringAsFixed(1)}%',
                    '30 days, from the 15-minute sweep',
                    Colors.teal.shade700,
                  ),
                  _Stat(
                    'stat-messages',
                    'Messages sent',
                    '${s.messagesSent}',
                    '${s.messagesPerDay} per day (encrypted)',
                    Colors.brown,
                  ),
                  _Stat(
                    'stat-critical',
                    'Critical alerts',
                    '${s.unresolvedCritical}',
                    'unresolved',
                    Colors.red.shade700,
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 16,
                runSpacing: 16,
                children: [
                  _Box(
                    key: const Key('panel-engagement'),
                    width: 640,
                    title: 'Platform engagement activity',
                    subtitle: 'Recorded actions per day, by user type',
                    child: _Engagement(days: s.dailyActivity),
                  ),
                  _Box(
                    key: const Key('panel-specialty'),
                    width: 380,
                    title: 'Usage by specialty',
                    subtitle: 'Doctors and their patients, by the doctor\'s specialty',
                    child: _Specialties(rows: s.bySpecialty, totalUsers: s.totalUsers),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat(this.keyName, this.title, this.value, this.note, this.color);

  final String keyName;
  final String title;
  final String value;
  final String note;
  final Color color;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 240,
    child: Card(
      key: Key(keyName),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: color, width: 2),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.labelLarge),
            Text(value, style: Theme.of(context).textTheme.displaySmall),
            Text(note),
          ],
        ),
      ),
    ),
  );
}

class _Box extends StatelessWidget {
  const _Box({
    super.key,
    required this.width,
    required this.title,
    required this.subtitle,
    required this.child,
  });

  final double width;
  final String title;
  final String subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: width,
    child: Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleLarge),
            Text(subtitle),
            const SizedBox(height: 16),
            SizedBox(height: 280, child: child),
          ],
        ),
      ),
    ),
  );
}

class _Engagement extends StatelessWidget {
  const _Engagement({required this.days});

  final List<(DateTime, Map<String, int>)> days;

  @override
  Widget build(BuildContext context) {
    final labels = [
      for (final (d, _) in days)
        days.length <= 7 ? _weekdays[d.weekday - 1] : '${d.day}/${d.month}',
    ];
    final step = (days.length / 8).ceil().clamp(1, 30);
    return Column(
      children: [
        Expanded(
          child: BarChart(
            BarChartData(
              gridData: const FlGridData(drawVerticalLine: false),
              borderData: FlBorderData(show: false),
              titlesData: FlTitlesData(
                topTitles: const AxisTitles(),
                rightTitles: const AxisTitles(),
                leftTitles: const AxisTitles(
                  sideTitles: SideTitles(showTitles: true, reservedSize: 32),
                ),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    getTitlesWidget: (v, _) {
                      final i = v.toInt();
                      return i >= 0 && i < labels.length && i % step == 0
                          ? Text(labels[i], style: const TextStyle(fontSize: 11))
                          : const SizedBox.shrink();
                    },
                  ),
                ),
              ),
              barGroups: [
                for (final (i, (_, counts)) in days.indexed)
                  BarChartGroupData(
                    x: i,
                    barRods: [
                      () {
                        var y = 0.0;
                        final items = <BarChartRodStackItem>[];
                        for (final (role, _, color) in _roles) {
                          final n = (counts[role] ?? 0).toDouble();
                          items.add(BarChartRodStackItem(y, y + n, color));
                          y += n;
                        }
                        return BarChartRodData(
                          toY: y,
                          width: days.length <= 7 ? 28 : 6,
                          rodStackItems: items,
                          color: Colors.transparent,
                          borderRadius: BorderRadius.zero,
                        );
                      }(),
                    ],
                  ),
              ],
            ),
          ),
        ),
        Wrap(
          spacing: 12,
          children: [
            for (final (_, label, color) in _roles)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.square, size: 10, color: color),
                  const SizedBox(width: 4),
                  Text(label),
                ],
              ),
          ],
        ),
      ],
    );
  }
}

class _Specialties extends StatelessWidget {
  const _Specialties({required this.rows, required this.totalUsers});

  final List<(String, int)> rows;
  final int totalUsers;

  static const _colors = [
    Color(0xFF0B6E99),
    Color(0xFF8D5A1F),
    Color(0xFF0E7C66),
    Color(0xFF7E57C2),
    Color(0xFFB0BEC5),
  ];

  @override
  Widget build(BuildContext context) {
    final total = rows.fold(0, (a, r) => a + r.$2);
    return Column(
      children: [
        Expanded(
          child: Stack(
            alignment: Alignment.center,
            children: [
              PieChart(
                PieChartData(
                  centerSpaceRadius: 50,
                  sectionsSpace: 2,
                  sections: total == 0
                      ? [PieChartSectionData(value: 1, color: Colors.grey.shade300, title: '')]
                      : [
                          for (final (i, (_, n)) in rows.indexed)
                            PieChartSectionData(
                              value: n.toDouble(),
                              color: _colors[i % _colors.length],
                              title: '',
                              radius: 28,
                            ),
                        ],
                ),
              ),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('$totalUsers', style: Theme.of(context).textTheme.headlineMedium),
                  const Text('total users'),
                ],
              ),
            ],
          ),
        ),
        if (rows.isEmpty) const Text('No activity yet.'),
        for (final (i, (name, n)) in rows.take(5).indexed)
          Row(
            key: Key('specialty-$name'),
            children: [
              Icon(Icons.circle, size: 10, color: _colors[i % _colors.length]),
              const SizedBox(width: 6),
              Expanded(child: Text(name)),
              Text('${(n / total * 100).round()}%'),
              const SizedBox(width: 12),
              SizedBox(width: 40, child: Text('$n', textAlign: TextAlign.end)),
            ],
          ),
      ],
    );
  }
}
