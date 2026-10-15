import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/enums.dart';
import '../../../core/utils/risk_style.dart';
import '../../../shared/services/api/api_client.dart';
import '../../dashboard/state/dashboard_providers.dart';
import '../../medications/domain/med_schedule.dart' show toMyt;
import '../../settings/state/settings_providers.dart';
import '../data/analytics_models.dart';
import '../state/admin_providers.dart';

const _months = [
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

String monthShort(String yyyyMm) {
  final m = int.tryParse(yyyyMm.split('-').last) ?? 1;
  return _months[(m - 1).clamp(0, 11)];
}

String _levelName(RiskLevel l) => switch (l) {
  RiskLevel.low => 'Low',
  RiskLevel.moderate => 'Moderate',
  RiskLevel.high => 'High',
  RiskLevel.critical => 'Critical',
};

/// UC11.5: pick a period, then download the hospital-wide PDF (E1: no data -> message).
Future<void> generateReport(BuildContext context, WidgetRef ref) async {
  final today = toMyt(ref.read(nowProvider)());
  final end = DateTime(today.year, today.month, today.day);
  final range = await showDateRangePicker(
    context: context,
    firstDate: DateTime(2025),
    lastDate: end,
    initialDateRange: DateTimeRange(start: end.subtract(const Duration(days: 29)), end: end),
    helpText: 'Report period (Malaysia time)',
  );
  if (range == null || !context.mounted) return;
  final messenger = ScaffoldMessenger.of(context);
  messenger.showSnackBar(const SnackBar(content: Text('Compiling the report…')));
  try {
    final pdf = await ref.read(adminRepositoryProvider).report(range.start, range.end);
    messenger.hideCurrentSnackBar();
    await ref
        .read(fileSharerProvider)
        .share(pdf, fileName: 'careflow-hospital-report.pdf', mimeType: 'application/pdf');
  } on ApiException catch (e) {
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(e.message)));
  } catch (_) {
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(content: Text('Could not generate the report.')));
  }
}

/// Hospital Analytics (Fig 4.3.14.5; FR-11.4; D-59).
class HospitalAnalyticsPage extends ConsumerWidget {
  const HospitalAnalyticsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(hospitalAnalyticsProvider);
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
                Text('Hospital Analytics', style: theme.textTheme.headlineSmall),
                const Text(
                  'Patient risk, consultation volume and medication adherence across the clinic.',
                ),
              ],
            ),
            FilledButton.icon(
              key: const Key('generate-report'),
              onPressed: () => generateReport(context, ref),
              icon: const Icon(Icons.picture_as_pdf_outlined),
              label: const Text('Generate full report'),
            ),
          ],
        ),
        const SizedBox(height: 16),
        data.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, _) => ListTile(
            leading: const Icon(Icons.cloud_off),
            title: const Text('Could not load analytics.'),
            trailing: TextButton(
              onPressed: () => ref.invalidate(hospitalAnalyticsProvider),
              child: const Text('Retry'),
            ),
          ),
          data: (h) => Wrap(
            spacing: 16,
            runSpacing: 16,
            children: [
              _Panel(
                key: const Key('panel-risk'),
                title: 'Patient risk distribution',
                subtitle: 'Latest assessment of each active patient',
                child: _RiskDonut(risk: h.risk, activePatients: h.activePatients),
              ),
              _Panel(
                key: const Key('panel-risk-trend'),
                title: 'Risk levels by month',
                subtitle: 'Patients assessed each month, by their last level that month',
                child: _RiskTrend(trend: h.riskTrend),
              ),
              _Panel(
                key: const Key('panel-consultations'),
                title: 'Consultation volume',
                subtitle: '6-month trend',
                child: _Consultations(months: h.consultations),
              ),
              _Panel(
                key: const Key('panel-adherence'),
                title: 'Medication adherence',
                subtitle: '30 days, doses taken of doses due',
                trailing: Text(
                  h.adherence == null ? '—' : '${h.adherence!.round()}%',
                  key: const Key('adherence-current'),
                  style: theme.textTheme.headlineSmall?.copyWith(color: Colors.teal.shade700),
                ),
                child: _Adherence(days: h.adherenceDaily),
              ),
              const _Panel(
                key: Key('panel-delivery'),
                title: 'Delivery success rate',
                subtitle: 'Pharmacy to patient home',
                child: Center(
                  child: Text(
                    'Available once medication ordering and delivery (Module 13) is live.',
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Panel extends StatelessWidget {
  const _Panel({
    super.key,
    required this.title,
    required this.subtitle,
    required this.child,
    this.trailing,
  });

  final String title;
  final String subtitle;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 520,
    child: Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: Theme.of(context).textTheme.titleLarge),
                      Text(subtitle),
                    ],
                  ),
                ),
                ?trailing,
              ],
            ),
            const SizedBox(height: 16),
            SizedBox(height: 240, child: child),
          ],
        ),
      ),
    ),
  );
}

class _RiskDonut extends StatelessWidget {
  const _RiskDonut({required this.risk, required this.activePatients});

  final RiskCounts risk;
  final int activePatients;

  @override
  Widget build(BuildContext context) {
    final total = risk.total;
    return Row(
      children: [
        Expanded(
          child: Stack(
            alignment: Alignment.center,
            children: [
              PieChart(
                PieChartData(
                  centerSpaceRadius: 60,
                  sectionsSpace: 2,
                  sections: total == 0
                      ? [PieChartSectionData(value: 1, color: Colors.grey.shade300, title: '')]
                      : [
                          for (final l in RiskLevel.values)
                            if (risk.counts[l]! > 0)
                              PieChartSectionData(
                                value: risk.counts[l]!.toDouble(),
                                color: riskColor(l),
                                title: '',
                                radius: 36,
                              ),
                        ],
                ),
              ),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('$total', style: Theme.of(context).textTheme.headlineMedium),
                  Text('of $activePatients patients', style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
            ],
          ),
        ),
        Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final l in RiskLevel.values)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Icon(Icons.circle, size: 10, color: riskColor(l)),
                    const SizedBox(width: 6),
                    Text(
                      '${_levelName(l)} ${risk.counts[l]}'
                      '${total == 0 ? '' : ' (${(risk.counts[l]! / total * 100).round()}%)'}',
                      key: Key('risk-${l.value}'),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ],
    );
  }
}

FlTitlesData _titles(List<String> labels) => FlTitlesData(
  topTitles: const AxisTitles(),
  rightTitles: const AxisTitles(),
  leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 32)),
  bottomTitles: AxisTitles(
    sideTitles: SideTitles(
      showTitles: true,
      getTitlesWidget: (v, _) {
        final i = v.toInt();
        return i >= 0 && i < labels.length ? Text(labels[i]) : const SizedBox.shrink();
      },
    ),
  ),
);

BarChartRodData _stack(List<(int, Color)> parts) {
  var y = 0.0;
  final items = <BarChartRodStackItem>[];
  for (final (n, color) in parts) {
    items.add(BarChartRodStackItem(y, y + n, color));
    y += n;
  }
  return BarChartRodData(
    toY: y,
    width: 22,
    rodStackItems: items,
    color: Colors.transparent,
    borderRadius: BorderRadius.zero,
  );
}

class _RiskTrend extends StatelessWidget {
  const _RiskTrend({required this.trend});

  final List<MonthRisk> trend;

  @override
  Widget build(BuildContext context) => BarChart(
    BarChartData(
      titlesData: _titles([for (final m in trend) monthShort(m.month)]),
      gridData: const FlGridData(drawVerticalLine: false),
      borderData: FlBorderData(show: false),
      barGroups: [
        for (final (i, m) in trend.indexed)
          BarChartGroupData(
            x: i,
            barRods: [
              _stack([for (final l in RiskLevel.values) (m.risk.counts[l]!, riskColor(l))]),
            ],
          ),
      ],
    ),
  );
}

class _Consultations extends StatelessWidget {
  const _Consultations({required this.months});

  final List<MonthConsultations> months;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Expanded(
        child: BarChart(
          BarChartData(
            titlesData: _titles([for (final m in months) monthShort(m.month)]),
            gridData: const FlGridData(drawVerticalLine: false),
            borderData: FlBorderData(show: false),
            barGroups: [
              for (final (i, m) in months.indexed)
                BarChartGroupData(
                  x: i,
                  barRods: [
                    _stack([
                      (m.completed, Colors.teal.shade600),
                      (m.noShow, Colors.orange.shade700),
                      (m.cancelled, Colors.grey),
                      (m.upcoming, Colors.blue.shade200),
                    ]),
                  ],
                ),
            ],
          ),
        ),
      ),
      const Wrap(
        spacing: 12,
        children: [
          _Legend('Completed', Colors.teal),
          _Legend('No-show', Colors.orange),
          _Legend('Cancelled', Colors.grey),
          _Legend('Upcoming', Colors.lightBlue),
        ],
      ),
    ],
  );
}

class _Legend extends StatelessWidget {
  const _Legend(this.label, this.color);

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(Icons.square, size: 10, color: color),
      const SizedBox(width: 4),
      Text(label),
    ],
  );
}

class _Adherence extends StatelessWidget {
  const _Adherence({required this.days});

  final List<(DateTime, double?)> days;

  @override
  Widget build(BuildContext context) {
    final points = [
      for (final (i, (_, rate)) in days.indexed)
        if (rate != null) FlSpot(i.toDouble(), rate),
    ];
    if (points.isEmpty) {
      return const Center(child: Text('No doses were due in the last 30 days.'));
    }
    return LineChart(
      LineChartData(
        minY: 0,
        maxY: 100,
        gridData: const FlGridData(drawVerticalLine: false),
        borderData: FlBorderData(show: false),
        titlesData: _titles([
          for (final (d, _) in days) '${d.day}/${d.month}',
        ]).copyWith(bottomTitles: const AxisTitles()),
        lineBarsData: [
          LineChartBarData(
            spots: points,
            color: Colors.teal.shade700,
            barWidth: 3,
            belowBarData: BarAreaData(show: true, color: Colors.teal.withValues(alpha: 0.15)),
          ),
        ],
      ),
    );
  }
}
