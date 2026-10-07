import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:app/core/api/app_exception.dart';

void main() {
  test('parses backend error details and status code', () {
    final request = RequestOptions(path: '/me');
    final error = DioException(
      requestOptions: request,
      response: Response(
        requestOptions: request,
        statusCode: 403,
        data: {
          'error': {
            'code': 'ACCOUNT_INACTIVE',
            'message': 'This account is inactive.',
            'details': {'reason': 'disabled'},
          },
        },
      ),
    );

    final exception = AppException.fromDioException(error);
    expect(exception.code, 'ACCOUNT_INACTIVE');
    expect(exception.message, 'This account is inactive.');
    expect(exception.statusCode, 403);
    expect(exception.details, {'reason': 'disabled'});
  });

  test('maps unreachable-server errors to a friendly network error', () {
    final exception = AppException.fromDioException(
      DioException.connectionError(
        requestOptions: RequestOptions(path: '/me'),
        reason: 'Connection refused',
      ),
    );

    expect(exception.code, 'NETWORK_ERROR');
    expect(exception.message, contains('Could not reach the server'));
  });
}
