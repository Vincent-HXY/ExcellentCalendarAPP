import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:excellent_calendar/auth/auth_refresh_token_adapter.dart';

void main() {
  group('AuthRefreshTokenAdapter', () {
    late AuthRefreshTokenAdapter adapter;

    setUp(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        MethodChannel('excellent_calendar/native'),
        null,
      );
      adapter = AuthRefreshTokenAdapter();
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        MethodChannel('excellent_calendar/native'),
        null,
      );
    });

    group('store()', () {
      test('should return successful result when channel responds', () async {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(
          MethodChannel('excellent_calendar/native'),
          (MethodCall methodCall) async {
            expect(methodCall.method, equals('auth.refresh_token.store'));
            expect(methodCall.arguments['refresh_token'], equals('test-token'));
            return {
              'native_result_available': true,
              'result': {
                'success': true,
                'data': {'performed': true},
              },
            };
          },
        );

        final result = await adapter.store(
          refreshToken: 'test-token',
          sessionId: 'session-1',
          expiresAt: '2026-12-31T00:00:00Z',
        );

        expect(result.isNativeResult, isTrue);
        expect(result.result.ok, isTrue);
        expect(result.result.data?.performed, isTrue);
      });

      test('should return local failure on PlatformException', () async {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(
          MethodChannel('excellent_calendar/native'),
          (MethodCall methodCall) async {
            throw PlatformException(code: 'STORAGE_ERROR', message: 'Failed to store');
          },
        );

        final result = await adapter.store(
          refreshToken: 'test-token',
          sessionId: 'session-1',
          expiresAt: '2026-12-31T00:00:00Z',
        );

        expect(result.isNativeResult, isFalse);
        expect(result.result.ok, isFalse);
      });
    });

    group('read()', () {
      test('should return stored token when available', () async {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(
          MethodChannel('excellent_calendar/native'),
          (MethodCall methodCall) async {
            expect(methodCall.method, equals('auth.refresh_token.read'));
            return {
              'native_result_available': true,
              'result': {
                'success': true,
                'data': {
                  'refresh_token': 'stored-token',
                  'session_id': 'session-1',
                  'expires_at': '2026-12-31T00:00:00Z',
                },
              },
            };
          },
        );

        final result = await adapter.read();

        expect(result.isNativeResult, isTrue);
        expect(result.result.ok, isTrue);
        expect(result.result.data?.refreshToken, equals('stored-token'));
        expect(result.result.data?.sessionId, equals('session-1'));
      });
    });

    group('delete()', () {
      test('should return successful result', () async {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(
          MethodChannel('excellent_calendar/native'),
          (MethodCall methodCall) async {
            expect(methodCall.method, equals('auth.refresh_token.delete'));
            return {
              'native_result_available': true,
              'result': {
                'success': true,
                'data': {'performed': true},
              },
            };
          },
        );

        final result = await adapter.delete();

        expect(result.isNativeResult, isTrue);
        expect(result.result.ok, isTrue);
      });
    });

    group('exists()', () {
      test('should return true when token exists', () async {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(
          MethodChannel('excellent_calendar/native'),
          (MethodCall methodCall) async {
            expect(methodCall.method, equals('auth.refresh_token.exists'));
            return {
              'native_result_available': true,
              'result': {
                'success': true,
                'data': {'exists': true},
              },
            };
          },
        );

        final result = await adapter.exists();

        expect(result.isNativeResult, isTrue);
        expect(result.result.ok, isTrue);
        expect(result.result.data?.exists, isTrue);
      });

      test('should return false when token does not exist', () async {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(
          MethodChannel('excellent_calendar/native'),
          (MethodCall methodCall) async {
            return {
              'native_result_available': true,
              'result': {
                'success': true,
                'data': {'exists': false},
              },
            };
          },
        );

        final result = await adapter.exists();

        expect(result.isNativeResult, isTrue);
        expect(result.result.ok, isTrue);
        expect(result.result.data?.exists, isFalse);
      });

      test('should return local failure on MissingPluginException', () async {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(
          MethodChannel('excellent_calendar/native'),
          (MethodCall methodCall) async {
            throw MissingPluginException('Plugin not registered');
          },
        );

        final result = await adapter.exists();

        expect(result.isNativeResult, isFalse);
        expect(result.result.ok, isFalse);
      });
    });
  });
}