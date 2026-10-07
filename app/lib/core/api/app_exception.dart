import 'package:dio/dio.dart';

class AppException implements Exception {
  const AppException({
    required this.code,
    required this.message,
    required this.details,
    this.statusCode,
  });

  final String code;
  final String message;
  final Map<String, Object?> details;
  final int? statusCode;

  factory AppException.fromDioException(DioException exception) {
    final data = exception.response?.data;
    if (data is Map) {
      final error = data['error'];
      if (error is Map &&
          error['code'] is String &&
          error['message'] is String) {
        final rawDetails = error['details'];
        return AppException(
          code: error['code'] as String,
          message: error['message'] as String,
          details: rawDetails is Map
              ? rawDetails.map((key, value) => MapEntry(key.toString(), value))
              : const {},
          statusCode: exception.response?.statusCode,
        );
      }
    }

    if (exception.response == null) {
      return const AppException(
        code: 'NETWORK_ERROR',
        message: 'Could not reach the server. Check your connection and try again.',
        details: {},
      );
    }

    return AppException(
      code: 'HTTP_ERROR',
      message: 'The server could not complete the request. Please try again.',
      details: const {},
      statusCode: exception.response?.statusCode,
    );
  }

  @override
  String toString() => 'AppException($code): $message';
}
