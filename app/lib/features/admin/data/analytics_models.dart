import '../../../core/constants/enums.dart';

int _int(Object? v) => (v as num?)?.toInt() ?? 0;

/// Patients per overall risk level.
class RiskCounts {
  const RiskCounts(this.counts);

  final Map<RiskLevel, int> counts;

  int get total => counts.values.fold(0, (a, b) => a + b);

  factory RiskCounts.fromJson(Map<String, dynamic> j) =>
      RiskCounts({for (final l in RiskLevel.values) l: _int(j[l.value])});
}

class MonthRisk {
  const MonthRisk(this.month, this.risk);

  /// yyyy-MM
  final String month;
  final RiskCounts risk;
}

class MonthConsultations {
  const MonthConsultations({
    required this.month,
    required this.completed,
    required this.noShow,
    required this.cancelled,
    required this.upcoming,
  });

  final String month;
  final int completed;
  final int noShow;
  final int cancelled;
  final int upcoming;
}

/// Hospital Analytics (Fig 4.3.14.5; FR-11.4; D-59).
class HospitalAnalytics {
  const HospitalAnalytics({
    required this.activePatients,
    required this.risk,
    required this.riskTrend,
    required this.consultations,
    required this.adherence,
    required this.adherenceDaily,
    this.delivery,
  });

  /// D-72: medication orders in the charted months (null for older servers).
  final DeliveryStats? delivery;

  final int activePatients;
  final RiskCounts risk;
  final List<MonthRisk> riskTrend;
  final List<MonthConsultations> consultations;
  final double? adherence;
  final List<(DateTime, double?)> adherenceDaily;

  factory HospitalAnalytics.fromJson(Map<String, dynamic> j) {
    final risk = Map<String, dynamic>.from(j['risk'] as Map? ?? const {});
    final adherence = Map<String, dynamic>.from(j['adherence'] as Map? ?? const {});
    return HospitalAnalytics(
      delivery: j['delivery'] is Map
          ? DeliveryStats.fromJson(Map<String, dynamic>.from(j['delivery'] as Map))
          : null,
      activePatients: _int(j['activePatients']),
      risk: RiskCounts.fromJson(Map<String, dynamic>.from(risk['counts'] as Map? ?? const {})),
      riskTrend: [
        for (final m in (j['riskTrend'] as List? ?? const []).cast<Map<dynamic, dynamic>>())
          MonthRisk('${m['month']}', RiskCounts.fromJson(Map<String, dynamic>.from(m))),
      ],
      consultations: [
        for (final m in (j['consultations'] as List? ?? const []).cast<Map<dynamic, dynamic>>())
          MonthConsultations(
            month: '${m['month']}',
            completed: _int(m['completed']),
            noShow: _int(m['noShow']),
            cancelled: _int(m['cancelled']),
            upcoming: _int(m['upcoming']),
          ),
      ],
      adherence: (adherence['current'] as num?)?.toDouble(),
      adherenceDaily: [
        for (final d in (adherence['daily'] as List? ?? const []).cast<Map<dynamic, dynamic>>())
          (DateTime.parse('${d['date']}'), (d['rate'] as num?)?.toDouble()),
      ],
    );
  }
}

/// System / usage analytics (Fig 4.3.14.6; FR-11.3; D-59).
class SystemAnalytics {
  const SystemAnalytics({
    required this.days,
    required this.activeClinicians,
    required this.totalClinicians,
    required this.messagesSent,
    required this.messagesPerDay,
    required this.unresolvedCritical,
    required this.totalUsers,
    required this.dailyActivity,
    required this.bySpecialty,
    this.uptime,
  });

  final int days;
  final int activeClinicians;
  final int totalClinicians;
  final int messagesSent;
  final double messagesPerDay;
  final int unresolvedCritical;
  final int totalUsers;
  final double? uptime;

  /// (day, role value -> events)
  final List<(DateTime, Map<String, int>)> dailyActivity;
  final List<(String, int)> bySpecialty;

  factory SystemAnalytics.fromJson(Map<String, dynamic> j) => SystemAnalytics(
    days: _int(j['days']),
    activeClinicians: _int(j['activeClinicians']),
    totalClinicians: _int(j['totalClinicians']),
    messagesSent: _int(j['messagesSent']),
    messagesPerDay: (j['messagesPerDay'] as num?)?.toDouble() ?? 0,
    unresolvedCritical: _int(j['unresolvedCritical']),
    totalUsers: _int(j['totalUsers']),
    uptime: (j['uptime'] as num?)?.toDouble(),
    dailyActivity: [
      for (final d in (j['dailyActivity'] as List? ?? const []).cast<Map<dynamic, dynamic>>())
        (
          DateTime.parse('${d['date']}'),
          {
            for (final e in d.entries)
              if (e.key != 'date') '${e.key}': _int(e.value),
          },
        ),
    ],
    bySpecialty: [
      for (final s in (j['bySpecialty'] as List? ?? const []).cast<Map<dynamic, dynamic>>())
        ('${s['specialty']}', _int(s['events'])),
    ],
  );
}

/// D-72 hospital analytics: medication orders and delivery.
class DeliveryStats {
  const DeliveryStats({
    required this.orders,
    required this.homeDelivery,
    required this.selfCollection,
    required this.paid,
    required this.delivered,
    required this.collected,
    required this.inProgress,
    required this.failed,
    required this.revenue,
    this.averageCourierFee,
  });

  final int orders;
  final int homeDelivery;
  final int selfCollection;
  final int paid;
  final int delivered;
  final int collected;
  final int inProgress;
  final int failed;
  final double revenue;
  final double? averageCourierFee;

  /// Delivered out of home deliveries that finished (delivered or failed).
  double? get successRate {
    final done = delivered + failed;
    return done == 0 ? null : delivered / done * 100;
  }

  factory DeliveryStats.fromJson(Map<String, dynamic> j) => DeliveryStats(
    orders: _int(j['orders']),
    homeDelivery: _int(j['homeDelivery']),
    selfCollection: _int(j['selfCollection']),
    paid: _int(j['paid']),
    delivered: _int(j['delivered']),
    collected: _int(j['collected']),
    inProgress: _int(j['inProgress']),
    failed: _int(j['failed']),
    revenue: (j['revenue'] as num?)?.toDouble() ?? 0,
    averageCourierFee: (j['averageCourierFee'] as num?)?.toDouble(),
  );
}
