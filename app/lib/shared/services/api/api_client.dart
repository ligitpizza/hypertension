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
  Future<Map<String, dynamic>> registerProfile({
    required String name,
    required String role,
    String? icNumber,
  }) => _post('/auth/register-profile', {'name': name, 'role': role, 'icNumber': ?icNumber});

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
  // ---- Module 11 admin panel (D-59) ----

  /// UC11.1: all users, optionally by role and search text.
  Future<Map<String, dynamic>> adminUsers({String? role, String? query}) =>
      _getQuery('/admin/users', {'role': ?role, if (query != null && query.isNotEmpty) 'q': query});

  /// UC11.3: audit entries with summary counts (query: from, to, action, userId, q, offset, limit).
  Future<Map<String, dynamic>> adminAuditLogs(Map<String, dynamic> query) =>
      _getQuery('/admin/audit-logs', query);

  /// FR-11.3: the same entries as CSV.
  Future<List<int>> adminAuditCsv(Map<String, dynamic> query) =>
      _bytes('/admin/audit-logs.csv', query);

  /// Fig 4.3.14.7: live check per service.
  Future<Map<String, dynamic>> adminSystemHealth() => _getQuery('/admin/system-health', const {});

  /// UC11.1: edit name / specialty / caseload limit, or (de)activate.
  Future<Map<String, dynamic>> updateUser(String uid, Map<String, dynamic> body) =>
      _send('PATCH', '/admin/users/$uid', body);

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

  // ---- Module 10 secure messaging (D-42) ----

  /// After a message is stored: push the recipient; escalate if the scan flagged it.
  Future<void> notifyMessage(String messageId) => _post('/messages/$messageId/notify', const {});

  /// D-44: risk before vs after the patient's first medicine (assigned doctor only).
  Future<Map<String, dynamic>> medicationEffect(String patientId) =>
      _get('/provider/patients/$patientId/medication-effect');

  /// D-50: the issuing doctor deletes their own prescription.
  Future<void> deletePrescription(String patientId, String prescriptionId) =>
      _send('DELETE', '/provider/patients/$patientId/prescriptions/$prescriptionId', null);

  // ---- D-50 patient-reported prescriptions ----

  Future<Map<String, dynamic>> reportPrescription(Map<String, dynamic> body) =>
      _post('/prescriptions/reported', body);

  Future<Map<String, dynamic>> updateReportedPrescription(String id, Map<String, dynamic> body) =>
      _send('PUT', '/prescriptions/reported/$id', body);

  Future<void> deleteReportedPrescription(String id) =>
      _send('DELETE', '/prescriptions/reported/$id', null);

  // ---- Module 7 appointments (FR-7.1-7.4, D-53) and assignment requests (D-54) ----

  Future<Map<String, dynamic>> appointmentSlots(String isoDate) =>
      _getQuery('/appointments/slots', {'date': isoDate});

  Future<Map<String, dynamic>> bookAppointment({
    required DateTime dateTime,
    required String type,
  }) => _post('/appointments', {'dateTime': dateTime.toUtc().toIso8601String(), 'type': type});

  /// UC7.2 / D-55: ask for a new time or a cancellation (with a reason), or withdraw.
  Future<Map<String, dynamic>> changeAppointment(
    String id, {
    DateTime? dateTime,
    bool cancel = false,
    bool withdraw = false,
    String? reason,
    String? note,
  }) => _send('PATCH', '/appointments/$id', {
    if (dateTime != null) 'dateTime': dateTime.toUtc().toIso8601String(),
    if (cancel) 'cancel': true,
    if (withdraw) 'withdraw': true,
    'reason': ?reason,
    if (note != null && note.trim().isNotEmpty) 'note': note.trim(),
  });

  /// D-55: the doctor or admin approves / declines a pending change.
  /// D-56: completed | no_show.
  Future<Map<String, dynamic>> recordAppointmentOutcome(String id, String outcome) =>
      _post('/appointments/$id/outcome', {'outcome': outcome});

  Future<Map<String, dynamic>> decideAppointment(
    String id, {
    required bool approve,
    String? note,
  }) => _post('/appointments/$id/decision', {
    'approve': approve,
    if (note != null && note.trim().isNotEmpty) 'note': note.trim(),
  });

  /// D-55: the doctor or admin cancels with a reason.
  Future<Map<String, dynamic>> staffCancelAppointment(String id, String reason) =>
      _post('/appointments/$id/staff-cancel', {'reason': reason.trim()});

  Future<Map<String, dynamic>> preVisitSummary(String appointmentId) =>
      _get('/appointments/$appointmentId/pre-visit-summary');

  Future<Map<String, dynamic>> requestDoctor() =>
      _post('/assignment-requests/new-doctor', const {});

  Future<Map<String, dynamic>> requestReassignment(
    String patientId, {
    String? proposedDoctorId,
    String? reason,
  }) => _post('/provider/patients/$patientId/reassignment-request', {
    'proposedDoctorId': ?proposedDoctorId,
    if (reason != null && reason.trim().isNotEmpty) 'reason': reason.trim(),
  });

  Future<Map<String, dynamic>> approveAssignment(String requestId, String doctorId) =>
      _post('/admin/assignment-requests/$requestId/approve', {'doctorId': doctorId});

  Future<Map<String, dynamic>> declineAssignment(String requestId, {String? reason}) => _post(
    '/admin/assignment-requests/$requestId/decline',
    {if (reason != null && reason.trim().isNotEmpty) 'reason': reason.trim()},
  );

  // ---- Module 5 medications (FR-5.1-5.4, D-43) ----

  /// UC5.1 / UC5.6: add; a MEDICATION_WARNINGS error carries duplicates and interactions
  /// until the patient resends with `acknowledgeWarnings`.
  Future<Map<String, dynamic>> addMedication(Map<String, dynamic> body) =>
      _post('/medications', body);

  Future<Map<String, dynamic>> updateMedication(String id, Map<String, dynamic> body) =>
      _send('PUT', '/medications/$id', body);

  Future<void> deleteMedication(String id) => _send('DELETE', '/medications/$id', null);

  /// UC5.3 step 3: confirm a scheduled dose, or (no time) an as-needed dose taken now.
  Future<Map<String, dynamic>> confirmDose(String id, {DateTime? scheduledTime}) => _post(
    '/medications/$id/doses',
    {if (scheduledTime != null) 'scheduledTime': scheduledTime.toUtc().toIso8601String()},
  );

  // ---- Module 12 settings (FR-12.1, FR-12.2; D-45 to D-47) ----

  Future<Map<String, dynamic>> updateProfile(Map<String, dynamic> body) =>
      _send('PUT', '/settings/profile', body);

  Future<Map<String, dynamic>> updateContact(Map<String, dynamic> body) =>
      _send('PUT', '/settings/contact', body);

  Future<Map<String, dynamic>> updateHealthProfile(Map<String, dynamic> body) =>
      _send('PUT', '/settings/health-profile', body);

  Future<Map<String, dynamic>> updateNotificationPrefs(Map<String, dynamic> body) =>
      _send('PUT', '/settings/notifications', body);

  /// UC12.3: the export file's bytes (pdf or json).
  Future<List<int>> exportData(String format) async {
    try {
      final res = await _dio.get<List<int>>(
        '/settings/export',
        queryParameters: {'format': format},
        options: Options(responseType: ResponseType.bytes, receiveTimeout: agentTimeout),
      );
      return res.data ?? const [];
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  // ---- Module 6 health records (D-58) ----

  Future<Map<String, dynamic>> createRecord({
    required String recordId,
    required String category,
    required String fileName,
  }) => _post('/records', {'recordId': recordId, 'category': category, 'fileName': fileName});

  Future<Map<String, dynamic>> setRecordCategory(String id, String category) =>
      _send('PATCH', '/records/$id', {'category': category});

  Future<void> deleteRecord(String id) => _send('DELETE', '/records/$id', null);

  Future<Map<String, dynamic>> shareRecord(String id) => _send('POST', '/records/$id/share', null);

  Future<Map<String, dynamic>> unshareRecord(String id) =>
      _send('DELETE', '/records/$id/share', null);

  /// UC6.3: the file's bytes (the patient's own, or a shared one for the doctor).
  Future<List<int>> recordFile(String id) async {
    try {
      final res = await _dio.get<List<int>>(
        '/records/$id/file',
        options: Options(responseType: ResponseType.bytes, receiveTimeout: agentTimeout),
      );
      return res.data ?? const [];
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  /// UC12.4: deactivate now, purge after 7 days (D-46).
  Future<Map<String, dynamic>> deleteAccount({bool acknowledgeRecurring = false}) =>
      _send('DELETE', '/settings/account?acknowledgeRecurring=$acknowledgeRecurring', null);

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

  Future<List<int>> _bytes(String path, Map<String, dynamic> query) async {
    try {
      final res = await _dio.get<List<int>>(
        path,
        queryParameters: query,
        options: Options(responseType: ResponseType.bytes, receiveTimeout: agentTimeout),
      );
      return res.data ?? const [];
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  Future<Map<String, dynamic>> _getQuery(String path, Map<String, dynamic> query) async {
    try {
      final res = await _dio.get<Map<String, dynamic>>(path, queryParameters: query);
      return res.data ?? const {};
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  Future<Map<String, dynamic>> _send(String method, String path, Map<String, dynamic>? body) async {
    try {
      final res = await _dio.request<Map<String, dynamic>>(
        path,
        data: body,
        options: Options(method: method),
      );
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
