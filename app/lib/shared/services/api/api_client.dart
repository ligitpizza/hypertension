import 'dart:convert';

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
    var data = e.response?.data;
    if (data is List<int>) {
      // Byte downloads (PDF, CSV) still return the JSON error envelope on failure.
      try {
        data = jsonDecode(utf8.decode(data));
      } catch (_) {}
    }
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

  /// Fig 4.3.14.5 (FR-11.4).
  Future<Map<String, dynamic>> adminHospitalAnalytics({int months = 6}) =>
      _getQuery('/admin/analytics/hospital', {'months': months});

  /// Fig 4.3.14.6 (FR-11.3).
  Future<Map<String, dynamic>> adminSystemAnalytics({int days = 7}) =>
      _getQuery('/admin/analytics/system', {'days': days});

  /// UC11.5: the hospital-wide PDF for Malaysian dates (yyyy-MM-dd).
  Future<List<int>> adminReport(String from, String to) async {
    try {
      final res = await _dio.post<List<int>>(
        '/admin/reports',
        data: {'from': from, 'to': to},
        options: Options(responseType: ResponseType.bytes, receiveTimeout: agentTimeout),
      );
      return res.data ?? const [];
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

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

  /// D-65: forgot password (works signed out; same answer whether or not the email exists).
  Future<Map<String, dynamic>> requestPasswordReset(String email) =>
      _post('/auth/password-reset', {'email': email});

  // ---- Module 3 (FR-3.1, FR-3.2) ----

  /// UC3.1: log a BP reading with optional PPG heart rate (UC3.3) and note (UC3.2).
  Future<Map<String, dynamic>> logReading({
    required int systolic,
    required int diastolic,
    int? heartRate,
    String? note,
    Map<String, double>? location,
  }) => _post('/vitals', {
    'systolic': systolic,
    'diastolic': diastolic,
    'heartRate': ?heartRate,
    if (note != null && note.trim().isNotEmpty) 'note': note.trim(),
    // D-62: GPS, kept by the backend only if the reading raises a family emergency.
    'location': ?location,
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

  /// D-69: a consolidated prescription of catalogue items
  /// ({catalogId, dose, frequency, quantity}).
  Future<Map<String, dynamic>> issueConsolidatedPrescription(
    String patientId, {
    required List<Map<String, dynamic>> items,
    bool isRecurring = false,
    bool acknowledgeInteractions = false,
  }) => _post('/provider/patients/$patientId/prescriptions', {
    'items': items,
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
    Map<String, double>? location,
  }) => _post('/triage', {
    'symptoms': symptoms,
    'severity': severity,
    'heartRate': heartRate,
    'vitalReadingId': vitalReadingId,
    'location': ?location,
  });

  // ---- FR-14.2 family monitoring (D-06, D-62) ----

  Future<Map<String, dynamic>> requestFamilyLink(String code) =>
      _post('/family/link-requests', {'code': code});

  Future<void> withdrawFamilyLink(String id) => _send('DELETE', '/family/link-requests/$id', null);

  Future<Map<String, dynamic>> decideFamilyLink(String id, {required bool approve}) =>
      _post('/family/link-requests/$id/${approve ? 'approve' : 'reject'}', const {});

  Future<void> unlinkFamily() => _send('DELETE', '/family/link', null);

  Future<void> removeFamilyMember(String uid) => _send('DELETE', '/family/members/$uid', null);

  Future<Map<String, dynamic>> sos({Map<String, double>? location, bool notifyFamily = true}) =>
      _post('/emergency/sos', {'location': ?location, 'notifyFamily': notifyFamily});

  Future<Map<String, dynamic>> openEmergencies() => _getQuery('/emergency/open', const {});

  Future<Map<String, dynamic>> updateEmergencyLocation(Map<String, double> location) =>
      _send('PUT', '/emergency/location', {'location': location});

  Future<Map<String, dynamic>> acknowledgeEmergency(String alertId) =>
      _post('/emergency/alerts/$alertId/acknowledge', const {});

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

  /// D-60: the admin books for a patient with any doctor at any minute.
  Future<Map<String, dynamic>> adminBookAppointment({
    required String patientId,
    required String doctorId,
    required DateTime dateTime,
    required String type,
  }) => _post('/admin/appointments', {
    'patientId': patientId,
    'doctorId': doctorId,
    'dateTime': dateTime.toUtc().toIso8601String(),
    'type': type,
  });

  /// D-60: the admin moves time, doctor or type instantly.
  Future<Map<String, dynamic>> adminEditAppointment(
    String id, {
    DateTime? dateTime,
    String? doctorId,
    String? type,
  }) => _send('PATCH', '/admin/appointments/$id', {
    if (dateTime != null) 'dateTime': dateTime.toUtc().toIso8601String(),
    'doctorId': ?doctorId,
    'type': ?type,
  });

  /// D-60: patient account opened by the admin.
  Future<Map<String, dynamic>> adminCreatePatient({
    required String name,
    required String email,
    required String icNumber,
  }) => _post('/admin/patients', {'name': name, 'email': email, 'icNumber': icNumber});

  /// D-61: one user with role-specific details.
  Future<Map<String, dynamic>> adminUserDetail(String uid) =>
      _getQuery('/admin/users/$uid', const {});

  /// D-60: permanent removal.
  Future<void> adminDeleteUser(String uid) => _send('DELETE', '/admin/users/$uid', null);

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

  // ---- Module 13 orders, payment and delivery (FR-13.x; D-66) ----

  Future<Map<String, dynamic>> myOrders() => _get('/orders');

  Future<Map<String, dynamic>> order(String id) => _get('/orders/$id');

  /// UC13.3: method is self_collection or home_delivery.
  /// D-67: home delivery also sends the phone's location and a contact number.
  Future<Map<String, dynamic>> confirmOrder(
    String id,
    String method, {
    String? address,
    double? lat,
    double? lng,
    String? phone,
  }) => _post('/orders/$id/confirm', {
    'method': method,
    'deliveryAddress': ?address,
    'deliveryLat': ?lat,
    'deliveryLng': ?lng,
    'deliveryPhone': ?phone,
  });

  /// D-71: the courier's fee for this drop-off (preview before confirming).
  Future<Map<String, dynamic>> deliveryQuote(
    String id, {
    required String address,
    required double lat,
    required double lng,
  }) => _post('/orders/$id/delivery-quote', {'deliveryAddress': address, 'lat': lat, 'lng': lng});

  /// UC13.2 A1.
  Future<void> skipOrder(String id) => _send('POST', '/orders/$id/skip', null);

  /// UC13.3: a PaymentIntent (mode stripe) or the simulated card form (mode fake).
  Future<Map<String, dynamic>> startPayment(String id) => _send('POST', '/orders/$id/pay', null);

  Future<Map<String, dynamic>> payFake(String id, String cardNumber) =>
      _post('/orders/$id/pay/fake', {'cardNumber': cardNumber});

  Future<Map<String, dynamic>> refreshPayment(String id) =>
      _send('POST', '/orders/$id/pay/refresh', null);

  /// FR-13.5.
  Future<Map<String, dynamic>> rescheduleDelivery(String id) =>
      _send('POST', '/orders/$id/reschedule', null);

  Future<void> switchToCollection(String id) =>
      _send('POST', '/orders/$id/switch-to-collection', null);

  /// D-66 testing aid (DEV_ORDER_TOOLS).
  Future<Map<String, dynamic>> devNextOrderCycle() => _send('POST', '/orders/dev/next-cycle', null);

  /// UC13.1: the doctor flags a prescription recurring (or stops it).
  Future<Map<String, dynamic>> setRecurring(String prescriptionId, bool recurring) =>
      _post('/prescriptions/$prescriptionId/recurring', {'isRecurring': recurring});

  /// UC13.6 pharmacist (Fig 4.3.13.1).
  Future<Map<String, dynamic>> pharmacyQueue() => _get('/pharmacy/queue');

  Future<Map<String, dynamic>> setMonthlyPrice(String prescriptionId, double price) =>
      _send('PUT', '/pharmacy/prescriptions/$prescriptionId/price', {'monthlyPrice': price});

  /// Catalogue orders take stock per item automatically (D-69): send no stock item.
  Future<Map<String, dynamic>> markOrderReady(String id, {String? stockItemId, int? units}) =>
      _post('/pharmacy/orders/$id/ready', {'stockItemId': ?stockItemId, 'units': ?units});

  Future<void> markOutOfStock(String id, {String? note}) =>
      _post('/pharmacy/orders/$id/out-of-stock', {'note': ?note});

  /// D-74: cancel an unpaid order with a reason (pharmacist, admin).
  Future<void> cancelOrder(String id, String reason) =>
      _post('/pharmacy/orders/$id/cancel', {'reason': reason});

  Future<void> markCollected(String id) => _send('POST', '/pharmacy/orders/$id/collected', null);

  Future<Map<String, dynamic>> pharmacyStock() => _get('/pharmacy/stock');

  Future<Map<String, dynamic>> addStockItem(Map<String, dynamic> body) =>
      _post('/pharmacy/stock', body);

  Future<Map<String, dynamic>> editStockItem(String id, Map<String, dynamic> body) =>
      _send('PATCH', '/pharmacy/stock/$id', body);

  Future<Map<String, dynamic>> receiveStock(String id, int units, String expiryDate) =>
      _post('/pharmacy/stock/$id/receive', {'units': units, 'expiryDate': expiryDate});

  Future<Map<String, dynamic>> pharmacyPatients(String query) =>
      _getQuery('/pharmacy/patients', {'q': query});

  // ---- D-69: catalogue, pharmacist patient view, pharmacy chat, address ----

  Future<Map<String, dynamic>> catalog() => _get('/catalog');

  Future<Map<String, dynamic>> addCatalogItem(Map<String, dynamic> body) => _post('/catalog', body);

  Future<Map<String, dynamic>> editCatalogItem(String id, Map<String, dynamic> body) =>
      _send('PATCH', '/catalog/$id', body);

  Future<Map<String, dynamic>> pharmacyPatient(String uid) => _get('/pharmacy/patients/$uid');

  /// D-70: every order by status group (pharmacist, admin).
  Future<Map<String, dynamic>> ordersOverview({String group = 'all', String query = ''}) =>
      _getQuery('/orders-overview', {'group': group, if (query.isNotEmpty) 'q': query});

  /// D-72 (M8): the patient's delivery preference for their doctor.
  Future<Map<String, dynamic>> deliveryPreference(String patientId) =>
      _get('/provider/patients/$patientId/delivery');

  /// D-72 (M11): the courier as configured on the server (read-only).
  Future<Map<String, dynamic>> adminCourier() => _get('/admin/courier');

  /// D-70: admin only.
  Future<void> deleteStockItem(String id) => _send('DELETE', '/pharmacy/stock/$id', null);

  Future<Map<String, dynamic>> myPharmacyChat() => _get('/pharmacy-chat/messages');

  Future<Map<String, dynamic>> sendPharmacyChat(String text) =>
      _post('/pharmacy-chat/messages', {'text': text});

  Future<Map<String, dynamic>> pharmacyConversations() => _get('/pharmacy-chat/conversations');

  Future<Map<String, dynamic>> pharmacyThread(String patientId) =>
      _get('/pharmacy-chat/$patientId/messages');

  Future<Map<String, dynamic>> sendPharmacyMessage(String patientId, String text) =>
      _post('/pharmacy-chat/$patientId/messages', {'text': text});

  Future<Map<String, dynamic>> updateAddress(String address, {double? lat, double? lng}) =>
      _send('PUT', '/settings/address', {'address': address, 'lat': lat, 'lng': lng});

  /// FR-11.4 delivery oversight (Fig 4.3.14.4).
  Future<Map<String, dynamic>> adminDeliveries() => _get('/admin/deliveries');

  Future<Map<String, dynamic>> adminDispatch(String id) =>
      _send('POST', '/admin/deliveries/$id/dispatch', null);

  Future<Map<String, dynamic>> adminSimulateFailure(String id) =>
      _post('/admin/deliveries/$id/simulate-failure', const {});

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
