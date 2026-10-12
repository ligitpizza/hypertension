import 'package:dio/dio.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// Error body returned by FastAPI: `{"error": {"code": "...", "message": "..."}}`
/// (docs/05 "FastAPI endpoints").
class ApiException implements Exception {
  ApiException(this.code, this.message, {this.statusCode});

  final String code;
  final String message;
  final int? statusCode;

  factory ApiException.fromDio(DioException e) {
    final data = e.response?.data;
    if (data is Map && data['error'] is Map) {
      final err = data['error'] as Map;
      return ApiException(
        '${err['code']}',
        '${err['message']}',
        statusCode: e.response?.statusCode,
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
    final dio = Dio(BaseOptions(
      baseUrl: '$baseUrl/api/v1',
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 15),
    ));
    if (auth != null) dio.interceptors.add(FirebaseAuthInterceptor(auth));
    return ApiClient(dio);
  }

  final Dio _dio;

  /// GET /api/v1/health — used by the walking skeleton and system health (FR-11.3).
  Future<Map<String, dynamic>> health() async {
    try {
      final res = await _dio.get<Map<String, dynamic>>('/health');
      return res.data ?? const {};
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }
}
