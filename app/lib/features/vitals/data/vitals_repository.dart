import '../../../core/constants/enums.dart';
import '../../../shared/services/api/api_client.dart';

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
  });

  final String id;
  final int systolic;
  final int diastolic;
  final int? heartRate;
  final BpCategory category;
  final AlertLevel? alertLevel;
  final DateTime loggedAt;

  factory LoggedReading.fromApi(Map<String, dynamic> j, DateTime now) => LoggedReading(
    id: j['id'] as String,
    systolic: j['systolic'] as int,
    diastolic: j['diastolic'] as int,
    heartRate: j['heartRate'] as int?,
    category: BpCategory.fromValue(j['category'] as String),
    alertLevel: j['alertLevel'] == null ? null : AlertLevel.fromValue(j['alertLevel'] as String),
    loggedAt: now,
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
