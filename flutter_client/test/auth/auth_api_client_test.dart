import 'package:flutter_test/flutter_test.dart';
import 'package:excellent_calendar/auth/auth_api_client.dart';
import 'package:excellent_calendar/auth/auth_http_client.dart';
import 'package:excellent_calendar/auth/auth_refresh_token_adapter.dart';

void main() {
  group('AuthResponseData.fromJson', () {
    test('should parse flat JSON response', () {
      final json = {
        'userId': '550e8400-e29b-41d4-a716-446655440000',
        'email': 'test@example.com',
        'username': 'testuser',
        'displayName': 'Test User',
        'avatarUrl': null,
        'language': 'en',
        'timezone': 'UTC',
        'emailVerified': true,
        'accessToken': 'eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxIn0',
        'refreshToken': 'eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxIn0',
        'expiresIn': 900,
      };

      final data = AuthResponseData.fromJson(json);

      expect(data.id, equals('550e8400-e29b-41d4-a716-446655440000'));
      expect(data.email, equals('test@example.com'));
      expect(data.username, equals('testuser'));
      expect(data.displayName, equals('Test User'));
      expect(data.avatarUrl, isNull);
      expect(data.emailVerified, isTrue);
      expect(data.accessToken, isNotEmpty);
      expect(data.refreshToken, isNotEmpty);
      expect(data.expiresIn, equals(900));
    });

    test('should handle missing optional fields', () {
      final json = {
        'userId': '550e8400-e29b-41d4-a716-446655440000',
        'email': 'test@example.com',
        'username': 'testuser',
        'displayName': 'Test User',
        'accessToken': 'access-token',
        'refreshToken': 'refresh-token',
      };

      final data = AuthResponseData.fromJson(json);

      expect(data.avatarUrl, isNull);
      expect(data.emailVerified, isFalse);
      expect(data.expiresIn, equals(900));
    });

    test('should fallback to id when userId is missing', () {
      final json = {
        'id': 'fallback-id',
        'email': 'test@example.com',
        'username': 'testuser',
        'displayName': 'Test User',
        'accessToken': 'access-token',
        'refreshToken': 'refresh-token',
      };

      final data = AuthResponseData.fromJson(json);

      expect(data.id, equals('fallback-id'));
    });
  });

  group('ProfileResponseData.fromJson', () {
    test('should parse flat JSON response', () {
      final json = {
        'userId': '550e8400-e29b-41d4-a716-446655440000',
        'email': 'test@example.com',
        'username': 'testuser',
        'displayName': 'Test User',
        'avatarUrl': null,
        'language': 'en',
        'timezone': 'UTC',
        'emailVerified': true,
      };

      final data = ProfileResponseData.fromJson(json);

      expect(data.id, equals('550e8400-e29b-41d4-a716-446655440000'));
      expect(data.email, equals('test@example.com'));
      expect(data.displayName, equals('Test User'));
      expect(data.emailVerified, isTrue);
    });

    test('should handle missing optional fields', () {
      final json = {
        'userId': '550e8400-e29b-41d4-a716-446655440000',
        'email': 'test@example.com',
        'username': 'testuser',
        'displayName': 'Test User',
      };

      final data = ProfileResponseData.fromJson(json);

      expect(data.avatarUrl, isNull);
      expect(data.emailVerified, isFalse);
    });
  });

  group('MessageResponseData.fromJson', () {
    test('should parse message response', () {
      final json = {'message': 'Operation successful'};

      final data = MessageResponseData.fromJson(json);

      expect(data.message, equals('Operation successful'));
    });

    test('should handle missing message', () {
      final data = MessageResponseData.fromJson({});

      expect(data.message, isEmpty);
    });
  });
}