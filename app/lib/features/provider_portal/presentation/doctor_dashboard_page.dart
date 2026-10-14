import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/enums.dart';
import '../../../core/utils/risk_style.dart';
import '../../dashboard/state/dashboard_providers.dart';
import '../domain/portal_logic.dart';
import '../domain/portal_models.dart';
import '../state/portal_providers.dart';
import 'portal_widgets.dart';

/// Fig 4.3.12.1 / 4.3.12.2 Doctor Dashboard (FR-8.1, FR-8.4; UC8.1, UC8.2, UC8.6).
class DoctorDashboardPage extends ConsumerStatefulWidget {
  const DoctorDashboardPage({super.key});

  @override
  ConsumerState<DoctorDashboardPage> createState() => _DoctorDashboardPageState();
}

class _DoctorDashboardPageState extends ConsumerState<DoctorDashboardPage> {
  final _search = TextEditingController();
  final Set<RiskLevel> _levels = {};

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _close(ClinicalAlert alert, ClinicalAlertStatus status) async {
    try {
      await ref.read(portalRepositoryProvider).closeAlert(alert.id, status);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not update the alert. Please try again.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final rows = ref.watch(patientRowsProvider);
    final alerts = ref.watch(openAlertsProvider);
    final now = ref.watch(nowProvider)();
    final all = rows.value ?? const <PatientRow>[];
    final names = {for (final r in all) r.patient.uid: r.patient.name};
    final banner = criticalBanner(alerts.value ?? const []);
    final wide = MediaQuery.sizeOf(context).width >= 1100;

    final main = <Widget>[
      if (banner != null)
        _CriticalBanner(
          alert: banner,
          patientName: names[banner.patientId],
          // Fig 4.3.12.2 / D-49: very high readings with poor adherence.
          poorAdherence: (alerts.value ?? const []).any(
            (a) => a.patientId == banner.patientId && a.type == ClinicalAlertType.lowAdherence,
          ),
          onReview: () => context.go('/doctor/patient/${banner.patientId}'),
          onDismiss: () => _close(banner, ClinicalAlertStatus.dismissed),
        ),
      _SummaryCards(rows: all, openAlerts: prioritiseAlerts(alerts.value ?? const []).length),
      const SizedBox(height: 16),
      _patientList(rows, now),
    ];
    final alertsPanel = _AlertsPanel(
      alerts: alerts,
      names: names,
      now: now,
      onReview: (a) => context.go('/doctor/patient/${a.patientId}'),
      onClose: _close,
    );

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (wide)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: 3, child: Column(children: main)),
              const SizedBox(width: 16),
              Expanded(flex: 2, child: alertsPanel),
            ],
          )
        else ...[
          ...main,
          const SizedBox(height: 16),
          alertsPanel,
        ],
      ],
    );
  }

  Widget _patientList(AsyncValue<List<PatientRow>> rows, DateTime now) {
    final counts = riskCounts(rows.value ?? const []);
    return SectionCard(
      title: 'My patients',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            key: const Key('patient-search'),
            controller: _search,
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search),
              hintText: 'Search patients by name',
              border: OutlineInputBorder(),
              isDense: true,
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilterChip(
                key: const Key('filter-all'),
                label: const Text('All'),
                selected: _levels.isEmpty,
                onSelected: (_) => setState(_levels.clear),
              ),
              for (final level in RiskLevel.values.reversed)
                FilterChip(
                  key: Key('filter-${level.value}'),
                  avatar: CircleAvatar(backgroundColor: riskColor(level), radius: 5),
                  label: Text('${riskLabel(level).replaceAll(' Risk', '')} (${counts[level]})'),
                  selected: _levels.contains(level),
                  onSelected: (on) =>
                      setState(() => on ? _levels.add(level) : _levels.remove(level)),
                ),
            ],
          ),
          const SizedBox(height: 12),
          AsyncSection(
            value: rows,
            isEmpty: (r) => r.isEmpty,
            emptyText: 'No patients are assigned to you yet.',
            builder: (all) {
              final shown = filterPatients(all, levels: _levels, query: _search.text);
              if (shown.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.all(8),
                  child: Text('No patients match this search or filter.'),
                );
              }
              return Column(
                children: [
                  for (final r in shown)
                    ListTile(
                      key: Key('patient-${r.patient.uid}'),
                      contentPadding: EdgeInsets.zero,
                      leading: CircleAvatar(
                        child: Text(r.patient.name.isEmpty ? '?' : r.patient.name[0].toUpperCase()),
                      ),
                      title: Text(r.patient.name),
                      subtitle: Text(
                        r.lastUpdate == null
                            ? 'No readings yet'
                            : 'Last update ${timeAgo(r.lastUpdate!, now)}',
                      ),
                      trailing: Wrap(
                        spacing: 12,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          if (r.emergency)
                            Chip(
                              key: Key('emergency-${r.patient.uid}'),
                              backgroundColor: riskColor(RiskLevel.critical),
                              label: const Text(
                                'EMERGENCY',
                                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                              ),
                            ),
                          BpText(reading: r.latestReading),
                          RiskChip(level: r.riskLevel),
                        ],
                      ),
                      onTap: () => context.go('/doctor/patient/${r.patient.uid}'),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _SummaryCards extends StatelessWidget {
  const _SummaryCards({required this.rows, required this.openAlerts});

  final List<PatientRow> rows;
  final int openAlerts;

  @override
  Widget build(BuildContext context) {
    final counts = riskCounts(rows);
    Widget card(String key, String label, int value, Color? color) => SizedBox(
      width: 180,
      child: Card(
        key: Key(key),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label),
              const SizedBox(height: 8),
              Text(
                '$value',
                style: Theme.of(
                  context,
                ).textTheme.headlineMedium?.copyWith(color: color, fontWeight: FontWeight.bold),
              ),
            ],
          ),
        ),
      ),
    );
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        card('count-total', 'Total patients', rows.length, null),
        card(
          'count-high',
          'High / critical risk',
          counts[RiskLevel.high]! + counts[RiskLevel.critical]!,
          riskColor(RiskLevel.critical),
        ),
        card(
          'count-moderate',
          'Moderate risk',
          counts[RiskLevel.moderate]!,
          riskColor(RiskLevel.moderate),
        ),
        card('count-alerts', 'Open alerts', openAlerts, Theme.of(context).colorScheme.error),
      ],
    );
  }
}

/// Fig 4.3.12.2: red banner for an open critical alert; Review or Dismiss.
class _CriticalBanner extends StatelessWidget {
  const _CriticalBanner({
    required this.alert,
    required this.patientName,
    required this.onReview,
    required this.onDismiss,
    this.poorAdherence = false,
  });

  final ClinicalAlert alert;
  final String? patientName;
  final bool poorAdherence;
  final VoidCallback onReview;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final color = riskColor(RiskLevel.critical);
    return Card(
      key: const Key('critical-banner'),
      color: color,
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.warning_amber_rounded, color: Colors.white),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'CRITICAL${patientName == null ? '' : ': $patientName'}',
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(alert.message, style: const TextStyle(color: Colors.white)),
            if (poorAdherence)
              const Padding(
                key: Key('banner-adherence'),
                padding: EdgeInsets.only(top: 4),
                child: Text(
                  'Combined with poor medication adherence (missed doses).',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                ),
              ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              children: [
                FilledButton(
                  key: const Key('banner-review'),
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: color,
                  ),
                  onPressed: onReview,
                  child: const Text('Review patient'),
                ),
                OutlinedButton(
                  key: const Key('banner-dismiss'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: const BorderSide(color: Colors.white),
                  ),
                  onPressed: onDismiss,
                  child: const Text('Dismiss'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// FR-8.4 priority alerts panel: most severe first, acknowledge or dismiss each.
class _AlertsPanel extends StatelessWidget {
  const _AlertsPanel({
    required this.alerts,
    required this.names,
    required this.now,
    required this.onReview,
    required this.onClose,
  });

  final AsyncValue<List<ClinicalAlert>> alerts;
  final Map<String, String> names;
  final DateTime now;
  final void Function(ClinicalAlert) onReview;
  final void Function(ClinicalAlert, ClinicalAlertStatus) onClose;

  @override
  Widget build(BuildContext context) {
    final count = prioritiseAlerts(alerts.value ?? const []).length;
    return SectionCard(
      title: 'Priority alerts',
      trailing: count == 0
          ? null
          : Badge(label: Text('$count'), backgroundColor: Theme.of(context).colorScheme.error),
      child: AsyncSection(
        value: alerts,
        isEmpty: (a) => prioritiseAlerts(a).isEmpty,
        emptyText: 'No open alerts.',
        builder: (a) => Column(
          children: [
            for (final alert in prioritiseAlerts(a))
              Card(
                key: Key('alert-${alert.id}'),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(color: riskColor(alert.severity), width: 2),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              '${alertTypeLabel(alert.type)} · ${names[alert.patientId] ?? 'Patient'}',
                              style: TextStyle(
                                color: riskColor(alert.severity),
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          Text(timeAgo(alert.createdAt, now)),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(alert.message),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        children: [
                          FilledButton.tonal(
                            onPressed: () => onReview(alert),
                            child: const Text('Review chart'),
                          ),
                          TextButton(
                            key: Key('ack-${alert.id}'),
                            onPressed: () => onClose(alert, ClinicalAlertStatus.acknowledged),
                            child: const Text('Acknowledge'),
                          ),
                          TextButton(
                            key: Key('dismiss-${alert.id}'),
                            onPressed: () => onClose(alert, ClinicalAlertStatus.dismissed),
                            child: const Text('Dismiss'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
