import 'package:flutter_test/flutter_test.dart';
import 'package:excellent_calendar/auth/auth_http_client.dart';

void main() {
  group('ApiResponse.fromHttpResponse', () {
    test('should parse wrapped response with data', () {
      final response = ApiResponse<Map<String, dynamic>>.fromHttpResponse(
        200,
        {'ok': true, 'data': {'id': '123'}},
        (json) => json,
        null,
      );

      expect(response.ok, isTrue);
      expect(response.data, isNotNull);
      expect(response.data!['id'], equals('123'));
    });

    test('should parse flat response (no data wrapper)', () {
      final response = ApiResponse<Map<String, dynamic>>.fromHttpResponse(
        200,
        {'id': '123', 'name': 'test'},
        (json) => json,
        null,
      );

      expect(response.ok, isTrue);
      expect(response.data, isNotNull);
      expect(response.data!['id'], equals('123'));
    });

    test('should handle error response', () {
      final response = ApiResponse<Map<String, dynamic>>.fromHttpResponse(
        401,
        {'ok': false, 'error': {'code': 'AUTH_INVALID_CREDENTIALS', 'message': 'Invalid'}},
        (json) => json,
        null,
      );

      expect(response.ok, isFalse);
      expect(response.error, isNotNull);
      expect(response.error!.code, equals('AUTH_INVALID_CREDENTIALS'));
    });

    test('should handle success response without parseData', () {
      final response = ApiResponse<void>.fromHttpResponse(
        200,
        {'ok': true, 'data': {'id': '123'}},
        null,
        null,
      );

      expect(response.ok, isTrue);
      expect(response.data, isNull);
    });

    test('should handle non-ok response without error field', () {
      final response = ApiResponse<Map<String, dynamic>>.fromHttpResponse(
        500,
        {'message': 'Internal error'},
        (json) => json,
        null,
      );

      expect(response.ok, isFalse);
      expect(response.error, isNull);
    });
  });

  group('BackendError', () {
    test('should parse from JSON', () {
      final error = BackendError.fromJson({
        'code': 'TEST_ERROR',
        'message': 'Test message',
        'retryable': true,
      });

      expect(error.code, equals('TEST_ERROR'));
      expect(error.message, equals('Test message'));
      expect(error.retryable, isTrue);
    });

    test('should provide defaults for missing fields', () {
      final error = BackendError.fromJson({});

      expect(error.code, equals('UNKNOWN'));
      expect(error.message, equals('Unknown error'));
    });

    test('isUnauthenticated should return true for API_UNAUTHENTICATED', () {
      final error = BackendError.fromJson({'code': 'API_UNAUTHENTICATED', 'message': ''});
      expect(error.isUnauthenticated, isTrue);
    });

    test('isSessionExpired should return true for AUTH_SESSION_EXPIRED', () {
      final error = BackendError.fromJson({'code': 'AUTH_SESSION_EXPIRED', 'message': ''});
      expect(error.isSessionExpired, isTrue);
    });

    test('isAuthInvalid should return true for AUTH_INVALID_CREDENTIALS', () {
      final error = BackendError.fromJson({'code': 'AUTH_INVALID_CREDENTIALS', 'message': ''});
      expect(error.isAuthInvalid, isTrue);
    });

    test('isRateLimited should return true for API_RATE_LIMITED', () {
      final error = BackendError.fromJson({'code': 'API_RATE_LIMITED', 'message': ''});
      expect(error.isRateLimited, isTrue);
    });

    test('should parse field errors', () {
      final error = BackendError.fromJson({
        'code': 'VALIDATION_ERROR',
        'message': 'Invalid fields',
        'field_errors': ['email: Invalid format', 'password: Too short'],
      });

      expect(error.fieldErrors.length, equals(2));
      expect(error.fieldErrors[0], equals('email: Invalid format'));
    });
  });
}