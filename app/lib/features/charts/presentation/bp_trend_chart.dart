import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../domain/trend_logic.dart';

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
const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

/// FR-4.1 BP trend line chart (systolic + diastolic), with an optional heart-rate
/// overlay (UC4.3) and dashed guide lines at 120 / 80 mmHg. Reused by the doctor
/// portal patient detail (Module 8).
class BpTrendChart extends StatelessWidget {
  const BpTrendChart({
    super.key,
    required this.points,
    required this.range,
    required this.now,
    this.showHeartRate = false,
  });

  final List<TrendPoint> points;
  final TrendRange range;
  final DateTime now;
  final bool showHeartRate;

  static const systolicColor = Color(0xFF1D6FA3);
  static const diastolicColor = Color(0xFF1D9E75);
  static const heartRateColor = Color(0xFFD85A30);

  double _x(DateTime t) => t.millisecondsSinceEpoch.toDouble();

  String _label(double x) {
    final d = DateTime.fromMillisecondsSinceEpoch(x.round());
    return switch (range) {
      TrendRange.week => _weekdays[d.weekday - 1],
      TrendRange.year => _months[d.month - 1],
      _ => '${d.day} ${_months[d.month - 1]}',
    };
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final minX = _x(range.startFrom(now));
    final maxX = _x(DateTime(now.year, now.month, now.day).add(const Duration(days: 1)));
    final values = [
      for (final p in points) ...[p.systolic, p.diastolic, if (showHeartRate) ?p.heartRate],
    ];
    final lo = values.isEmpty ? 60.0 : values.reduce((a, b) => a < b ? a : b);
    final hi = values.isEmpty ? 160.0 : values.reduce((a, b) => a > b ? a : b);
    final minY = ((lo - 10) / 20).floor() * 20.0;
    final maxY = ((hi + 10) / 20).ceil() * 20.0;

    LineChartBarData line(List<FlSpot> spots, Color color, {bool dashed = false}) =>
        LineChartBarData(
          spots: spots,
          color: color,
          barWidth: 3,
          isCurved: spots.length > 2,
          preventCurveOverShooting: true,
          dashArray: dashed ? [6, 4] : null,
          dotData: FlDotData(show: spots.length <= 31),
        );

    final hrSpots = [
      for (final p in points)
        if (p.heartRate != null) FlSpot(_x(p.time), p.heartRate!),
    ];

    return Semantics(
      label: 'Blood pressure trend chart, ${points.length} points, ${range.label}',
      child: LineChart(
        key: const Key('bp-trend-chart'),
        LineChartData(
          minX: minX,
          maxX: maxX,
          minY: minY,
          maxY: maxY,
          lineBarsData: [
            line([for (final p in points) FlSpot(_x(p.time), p.systolic)], systolicColor),
            line([for (final p in points) FlSpot(_x(p.time), p.diastolic)], diastolicColor),
            if (showHeartRate && hrSpots.isNotEmpty) line(hrSpots, heartRateColor, dashed: true),
          ],
          extraLinesData: ExtraLinesData(
            horizontalLines: [
              for (final y in [120.0, 80.0])
                if (y > minY && y < maxY)
                  HorizontalLine(
                    y: y,
                    color: scheme.outline.withValues(alpha: 0.6),
                    strokeWidth: 1,
                    dashArray: [4, 4],
                  ),
            ],
          ),
          gridData: FlGridData(
            drawVerticalLine: false,
            horizontalInterval: 20,
            getDrawingHorizontalLine: (_) =>
                FlLine(color: scheme.outlineVariant.withValues(alpha: 0.4), strokeWidth: 1),
          ),
          borderData: FlBorderData(show: false),
          titlesData: FlTitlesData(
            topTitles: const AxisTitles(),
            rightTitles: const AxisTitles(),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 36,
                interval: 20,
                getTitlesWidget: (v, meta) =>
                    SideTitleWidget(meta: meta, child: Text(v.toInt().toString())),
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 28,
                interval: (maxX - minX) / (range == TrendRange.week ? 6 : 4),
                getTitlesWidget: (v, meta) => SideTitleWidget(
                  meta: meta,
                  child: Text(_label(v), style: const TextStyle(fontSize: 11)),
                ),
              ),
            ),
          ),
          lineTouchData: LineTouchData(
            touchTooltipData: LineTouchTooltipData(
              getTooltipItems: (spots) => [
                for (final s in spots)
                  LineTooltipItem(
                    '${s.y.round()}${s.barIndex == 2 ? ' bpm' : ''}',
                    TextStyle(color: s.bar.color, fontWeight: FontWeight.bold),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Small coloured legend item.
class ChartLegend extends StatelessWidget {
  const ChartLegend({super.key, required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      CircleAvatar(radius: 5, backgroundColor: color),
      const SizedBox(width: 6),
      Text(label),
    ],
  );
}
