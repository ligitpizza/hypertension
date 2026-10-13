import 'package:dio/dio.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// Error body returned by FastAPI: `{"error": {"code": "...", "message": "..."}}`
/// (docs/05 "FastAPI endpoints").
class ApiException implements Exception {
  ApiException(this.code, this.message, {this.statusCode, this.details});

  final String code;
  final String message;
  final int? statusCode;

  /// Optional structured context, e.g. drug interactions (UC8.4 E1).
  final Object? details;

  factory ApiException.fromDio(DioException e) {
    final data = e.response?.data;
    if (data is Map && data['error'] is Map) {
      final err = data['error'] as Map;
      return ApiException(
        '${err['code']}',
        '${err['message']}',
        statusCode: e.response?.statusCode,
        details: err['details'],
      );
    }
    return ApiException(
      'NETWORK_ERROR',
      e.message ?? 'Could not reach the server.',
      statusCode: e.response?.statusCode,
    );
  }

  @override
  String toString() => 'ApiException($code, $message)';
}

/// Attaches the Firebase ID token as `Authorization: Bearer <idToken>` so
/// FastAPI can verify the caller and read the `role` claim (docs/05).
class FirebaseAuthInterceptor extends Interceptor {
  FirebaseAuthInterceptor(this._auth);

  final FirebaseAuth _auth;

  @override
  Future<void> onRequest(RequestOptions options, RequestInterceptorHandler handler) async {
    final token = await _auth.currentUser?.getIdToken();
    if (token != null) {
      options.headers['Authorization'] = 'Bearer $token';
    }
    handler.next(options);
  }
}

/// Thin wrapper over the FastAPI `/api/v1` surface. Feature modules add their
/// own methods here (or a retrofit client) as they are built.
class ApiClient {
  ApiClient(this._dio);

  factory ApiClient.create({required String baseUrl, FirebaseAuth? auth}) {
    final dio = Dio(
      BaseOptions(
        baseUrl: '$baseUrl/api/v1',
        connectTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 15),
      ),
    );
    if (auth != null) dio.interceptors.add(FirebaseAuthInterceptor(auth));
    return ApiClient(dio);
  }

  final Dio _dio;

  /// GET /api/v1/health — used by the walking skeleton and system health (FR-11.3).
  Future<Map<String, dynamic>> health() => _get('/health');

  // ---- Module 1 (FR-1.1 to FR-1.6) ----

  /// UC1.1: create the users doc and role claim after Firebase sign-up.
  Future<Map<String, dynamic>> registerProfile({required String name, required String role}) =>
      _post('/auth/register-profile', {'name': name, 'role': role});

  /// UC1.4: submit the onboarding health profile (D-25 shape).
  Future<Map<String, dynamic>> completeOnboarding(Map<String, dynamic> body) =>
      _post('/auth/onboarding', body);

  /// FR-1.5: audit LOGIN / LOGOUT; LOGIN also enforces app match and active account.
  Future<Map<String, dynamic>> sessionEvent({required String event, required String app}) =>
      _post('/auth/session-events', {'event': event, 'app': app});

  /// D-27: report a failed sign-in (unauthenticated; backend stores the email domain only).
  Future<void> reportLoginFailed({
    required String email,
    required String reason,
    required String app,
  }) => _post('/auth/login-failed', {'email': email, 'reason': reason, 'app': app});

  /// UC1.5: admin creates a staff account.
  Future<Map<String, dynamic>> createStaff({
    required String name,
    required String email,
    required String role,
    String? specialty,
  }) => _post('/admin/staff', {
    'name': name,
    'email': email,
    'role': role,
    if (specialty != null && specialty.isNotEmpty) 'specialty': specialty,
  });

  // ---- Module 3 (FR-3.1, FR-3.2) ----

  /// UC3.1: log a BP reading with optional PPG heart rate (UC3.3) and note (UC3.2).
  Future<Map<String, dynamic>> logReading({
    required int systolic,
    required int diastolic,
    int? heartRate,
    String? note,
  }) => _post('/vitals', {
    'systolic': systolic,
    'diastolic': diastolic,
    'heartRate': ?heartRate,
    if (note != null && note.trim().isNotEmpty) 'note': note.trim(),
  });

  // ---- Module 8 doctor actions (FR-8.3) ----

  /// UC8.4: clinical note for an assigned patient.
  Future<Map<String, dynamic>> addClinicalNote(String patientId, String content) =>
      _post('/provider/patients/$patientId/notes', {'content': content});

  /// UC8.5: replace the patient's single living care plan.
  Future<Map<String, dynamic>> updateCarePlan(String patientId, String content) async {
    try {
      final res = await _dio.put<Map<String, dynamic>>(
        '/provider/patients/$patientId/care-plan',
        data: {'content': content},
      );
      return res.data ?? const {};
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  /// UC8.4: throws ApiException('DRUG_INTERACTION') with `details` until acknowledged (E1).
  Future<Map<String, dynamic>> issuePrescription(
    String patientId, {
    required String medicationName,
    required String dosage,
    required String frequency,
    String? duration,
    bool isRecurring = false,
    bool acknowledgeInteractions = false,
  }) => _post('/provider/patients/$patientId/prescriptions', {
    'medicationName': medicationName,
    'dosage': dosage,
    'frequency': frequency,
    if (duration != null && duration.trim().isNotEmpty) 'duration': duration.trim(),
    'isRecurring': isRecurring,
    'acknowledgeInteractions': acknowledgeInteractions,
  });

  // ---- FR-14.3 Symptom checker (D-36) ----

  /// UC14.1/UC14.3: symptom ids from symptom_catalog, severity, the heart rate and the id
  /// of the BP reading just logged in the checker (both compulsory, D-38).
  Future<Map<String, dynamic>> submitTriage({
    required List<String> symptoms,
    required String severity,
    required int heartRate,
    required String vitalReadingId,
  }) => _post('/triage', {
    'symptoms': symptoms,
    'severity': severity,
    'heartRate': heartRate,
    'vitalReadingId': vitalReadingId,
  });

  // ---- FR-14.1 AI Health Agent (D-34) ----

  /// UC2.6: {reply, emergency, fallback}.
  Future<Map<String, dynamic>> agentChat(String message) =>
      _post('/agent/chat', {'message': message}, receiveTimeout: agentTimeout);

  /// UC2.7: {text, riskLevel, actions, fallback} for the latest reading.
  Future<Map<String, dynamic>> agentProactive() =>
      _post('/agent/proactive', const {}, receiveTimeout: agentTimeout);

  /// Gemini plus one server-side retry can take ~25 s at busy times.
  static const agentTimeout = Duration(seconds: 35);

  // ---- Module 9 push notifications (D-33) ----

  Future<void> registerFcmToken({required String token, required String platform}) =>
      _post('/devices/fcm-token', {'token': token, 'platform': platform});

  Future<void> removeFcmToken({required String token, required String platform}) async {
    try {
      await _dio.delete<void>('/devices/fcm-token', data: {'token': token, 'platform': platform});
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  Future<Map<String, dynamic>> _get(String path) async {
    try {
      final res = await _dio.get<Map<String, dynamic>>(path);
      return res.data ?? const {};
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  Future<Map<String, dynamic>> _post(
    String path,
    Map<String, dynamic> body, {
    Duration? receiveTimeout,
  }) async {
    try {
      final res = await _dio.post<Map<String, dynamic>>(
        path,
        data: body,
        options: receiveTimeout == null ? null : Options(receiveTimeout: receiveTimeout),
      );
      return res.data ?? const {};
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }
}
