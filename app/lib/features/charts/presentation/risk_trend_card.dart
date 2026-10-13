import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../../core/constants/enums.dart';
import '../../../core/utils/risk_style.dart';
import '../../../shared/models/health_models.dart';
import '../domain/trend_logic.dart';
import 'bp_trend_chart.dart';

const complicationNames = {
  Complication.stroke: 'Stroke',
  Complication.cad: 'Coronary artery disease',
  Complication.heartFailure: 'Heart failure',
  Complication.ckd: 'Kidney disease',
  Complication.t2d: 'Type 2 diabetes',
};

const _seriesColors = {
  Complication.stroke: Color(0xFFA32D2D),
  Complication.cad: Color(0xFF1D6FA3),
  Complication.heartFailure: Color(0xFFD85A30),
  Complication.ckd: Color(0xFF7B5EA7),
  Complication.t2d: Color(0xFF1D9E75),
};

/// FR-4.3 / UC4.4 risk score trend per complication. Empty until Module 9 writes scores;
/// a single score is shown without a line (UC4.4 E1).
class RiskTrendCard extends StatelessWidget {
  const RiskTrendCard({super.key, required this.scores});

  /// Newest first, as returned by the repository.
  final List<RiskScore> scores;

  @override
  Widget build(BuildContext context) {
    return Card(
      key: const Key('risk-trend-card'),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Risk Score Trend', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            if (scores.isEmpty)
              const Text(
                key: Key('risk-trend-empty'),
                'Pending data. Your risk scores will appear here once your risk assessment '
                'is generated from your readings.',
              )
            else if (scores.length == 1)
              _Single(score: scores.first)
            else
              _Chart(scores: scores),
            const SizedBox(height: 8),
            const Text(
              'Risk scores are estimates from a statistical model, not a diagnosis.',
              style: TextStyle(fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}

class _Single extends StatelessWidget {
  const _Single({required this.score});

  final RiskScore score;

  @override
  Widget build(BuildContext context) {
    final level = score.overallLevel;
    return Column(
      key: const Key('risk-trend-single'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Chip(
          avatar: CircleAvatar(backgroundColor: riskColor(level), radius: 5),
          label: Text(riskLabel(level)),
        ),
        for (final e in score.scores.entries)
          Text('${complicationNames[e.key]}: ${riskPercent(e.value.value)}'),
        const Text('A trend line appears after your next risk assessment.'),
      ],
    );
  }
}

class _Chart extends StatelessWidget {
  const _Chart({required this.scores});

  final List<RiskScore> scores;

  @override
  Widget build(BuildContext context) {
    final series = riskSeries(scores);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 180,
          child: LineChart(
            key: const Key('risk-trend-chart'),
            LineChartData(
              minY: 0,
              maxY: 100,
              lineBarsData: [
                for (final e in series.entries)
                  LineChartBarData(
                    spots: [
                      for (final (t, v) in e.value)
                        FlSpot(t.millisecondsSinceEpoch.toDouble(), v * 100),
                    ],
                    color: _seriesColors[e.key],
                    barWidth: 2,
                    dotData: const FlDotData(show: true),
                  ),
              ],
              gridData: const FlGridData(drawVerticalLine: false, horizontalInterval: 25),
              borderData: FlBorderData(show: false),
              titlesData: FlTitlesData(
                topTitles: const AxisTitles(),
                rightTitles: const AxisTitles(),
                bottomTitles: const AxisTitles(),
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 36,
                    interval: 25,
                    getTitlesWidget: (v, meta) =>
                        SideTitleWidget(meta: meta, child: Text('${v.toInt()}%')),
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 12,
          runSpacing: 4,
          children: [
            for (final c in series.keys)
              ChartLegend(color: _seriesColors[c]!, label: complicationNames[c]!),
          ],
        ),
      ],
    );
  }
}
