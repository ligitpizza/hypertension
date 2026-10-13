import '../../../core/constants/enums.dart';
import '../../../shared/services/api/api_client.dart';

/// Risk score generated after the reading (UC9.1), as returned by the API.
class ReadingRisk {
  const ReadingRisk({
    required this.overall,
    required this.scores,
    this.lowConfidence = false,
    this.diagnosed = const {},
  });

  final RiskLevel overall;
  final Map<Complication, ({double value, RiskLevel level})> scores;
  final bool lowConfidence;

  /// Conditions already diagnosed at onboarding: shown as such, not as a risk.
  final Set<Complication> diagnosed;

  factory ReadingRisk.fromApi(Map<String, dynamic> j) => ReadingRisk(
    overall: RiskLevel.fromValue(j['overallLevel'] as String),
    scores: {
      for (final e in (j['scores'] as Map<String, dynamic>).entries)
        Complication.fromValue(e.key): (
          value: ((e.value as Map)['value'] as num).toDouble(),
          level: RiskLevel.fromValue((e.value as Map)['level'] as String),
        ),
    },
    lowConfidence: j['lowConfidence'] as bool? ?? false,
    diagnosed: {
      for (final c in (j['diagnosed'] as List<dynamic>? ?? const []))
        Complication.fromValue(c as String),
    },
  );
}

/// Result of POST /api/v1/vitals.
class LoggedReading {
  const LoggedReading({
    required this.id,
    required this.systolic,
    required this.diastolic,
    required this.category,
    required this.loggedAt,
    this.heartRate,
    this.alertLevel,
    this.risk,
    this.readingsUntilRisk = 0,
    this.recommendations = const [],
    this.bookAppointmentPrompt = false,
  });

  final String id;
  final int systolic;
  final int diastolic;
  final int? heartRate;
  final BpCategory category;
  final AlertLevel? alertLevel;
  final DateTime loggedAt;

  /// Null until the patient has three readings (or the models are unavailable).
  final ReadingRisk? risk;
  final int readingsUntilRisk;

  /// FR-9.4 tips; the last one is the not-a-doctor disclaimer.
  final List<String> recommendations;

  /// UC9.2/UC9.3: high reading or risk, suggest booking (FR-7.5 in Increment 3).
  final bool bookAppointmentPrompt;

  factory LoggedReading.fromApi(Map<String, dynamic> j, DateTime now) => LoggedReading(
    id: j['id'] as String,
    systolic: j['systolic'] as int,
    diastolic: j['diastolic'] as int,
    heartRate: j['heartRate'] as int?,
    category: BpCategory.fromValue(j['category'] as String),
    alertLevel: j['alertLevel'] == null ? null : AlertLevel.fromValue(j['alertLevel'] as String),
    loggedAt: now,
    risk: j['risk'] == null ? null : ReadingRisk.fromApi(j['risk'] as Map<String, dynamic>),
    readingsUntilRisk: j['readingsUntilRisk'] as int? ?? 0,
    recommendations: [
      for (final r in j['recommendations'] as List<dynamic>? ?? const []) r as String,
    ],
    bookAppointmentPrompt: j['bookAppointmentPrompt'] as bool? ?? false,
  );
}

/// Writes go through FastAPI (validation, audit, and risk scoring from Increment 2).
abstract interface class VitalsRepository {
  Future<LoggedReading> logReading({
    required int systolic,
    required int diastolic,
    int? heartRate,
    String? note,
  });
}

class ApiVitalsRepository implements VitalsRepository {
  ApiVitalsRepository(this._api);

  final ApiClient _api;

  @override
  Future<LoggedReading> logReading({
    required int systolic,
    required int diastolic,
    int? heartRate,
    String? note,
  }) async {
    final res = await _api.logReading(
      systolic: systolic,
      diastolic: diastolic,
      heartRate: heartRate,
      note: note,
    );
    return LoggedReading.fromApi(res, DateTime.now());
  }
}
