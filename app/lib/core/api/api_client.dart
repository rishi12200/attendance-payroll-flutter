import 'package:dio/dio.dart';

import 'app_exception.dart';
import '../../features/auth/domain/profile_api.dart';
import '../../features/auth/domain/user_profile.dart';

const apiBaseUrl = String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: 'http://10.0.2.2:8080',
);

typedef IdTokenProvider = Future<String?> Function({
  required bool forceRefresh,
});
typedef UnauthorizedHandler = Future<void> Function();

abstract interface class ApiTransport {
  Future<Object?> getJson(
    String path, {
    Map<String, Object?>? queryParameters,
  });

  Future<Object?> postJson(String path, {Object? data});

  Future<Object?> patchJson(String path, {Object? data});
}

class ApiClient implements ProfileApi, ApiTransport {
  ApiClient({
    required IdTokenProvider getIdToken,
    required UnauthorizedHandler onUnauthorized,
    String baseUrl = apiBaseUrl,
    Dio? dio,
  }) : dio = dio ?? Dio(BaseOptions(baseUrl: baseUrl)) {
    this.dio.interceptors.add(
      _AuthInterceptor(
        dio: this.dio,
        getIdToken: getIdToken,
        onUnauthorized: onUnauthorized,
      ),
    );
  }

  final Dio dio;

  @override
  Future<Object?> getJson(
    String path, {
    Map<String, Object?>? queryParameters,
  }) async {
    final response = await dio.get<dynamic>(
      path,
      queryParameters: queryParameters,
    );
    return response.data;
  }

  @override
  Future<Object?> postJson(String path, {Object? data}) async {
    final response = await dio.post<dynamic>(path, data: data);
    return response.data;
  }

  @override
  Future<Object?> patchJson(String path, {Object? data}) async {
    final response = await dio.patch<dynamic>(path, data: data);
    return response.data;
  }

  @override
  Future<UserProfile> getMe() async {
    try {
      final response = await dio.get<Map<String, dynamic>>('/me');
      final data = response.data;
      if (data == null) {
        throw const AppException(
          code: 'INVALID_RESPONSE',
          message: 'The server returned an invalid profile.',
          details: {},
        );
      }
      try {
        return UserProfile.fromJson(data);
      } on FormatException {
        throw const AppException(
          code: 'INVALID_RESPONSE',
          message: 'The server returned an invalid profile.',
          details: {},
        );
      }
    } on DioException catch (error) {
      throw AppException.fromDioException(error);
    }
  }
}

class _AuthInterceptor extends Interceptor {
  _AuthInterceptor({
    required this.dio,
    required this.getIdToken,
    required this.onUnauthorized,
  });

  static const _retriedAfterRefresh = 'retriedAfterTokenRefresh';
  static const _refreshedToken = 'refreshedIdToken';

  final Dio dio;
  final IdTokenProvider getIdToken;
  final UnauthorizedHandler onUnauthorized;

  @override
  Future<void> onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    final refreshedToken = options.extra[_refreshedToken];
    final token = refreshedToken is String
        ? refreshedToken
        : await getIdToken(forceRefresh: false);
    if (token != null && token.isNotEmpty) {
      options.headers['Authorization'] = 'Bearer $token';
    }
    handler.next(options);
  }

  @override
  Future<void> onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    if (err.response?.statusCode != 401) {
      handler.next(err);
      return;
    }

    final request = err.requestOptions;
    if (request.extra[_retriedAfterRefresh] == true) {
      await onUnauthorized();
      handler.next(err);
      return;
    }

    request.extra[_retriedAfterRefresh] = true;
    String? token;
    try {
      token = await getIdToken(forceRefresh: true);
    } catch (refreshError) {
      await onUnauthorized();
      handler.next(
        DioException(
          requestOptions: request,
          response: err.response,
          type: err.type,
          message: err.message,
          error: refreshError,
        ),
      );
      return;
    }
    if (token == null || token.isEmpty) {
      await onUnauthorized();
      handler.next(err);
      return;
    }

    request.extra[_refreshedToken] = token;
    request.headers['Authorization'] = 'Bearer $token';
    try {
      final response = await dio.fetch<dynamic>(request);
      handler.resolve(response);
    } on DioException catch (retryError) {
      handler.next(retryError);
    }
  }
}
