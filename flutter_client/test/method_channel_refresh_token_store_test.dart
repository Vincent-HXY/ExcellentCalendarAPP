import 'package:excellent_calendar/boundary_adapters/dart_method_channel/native_method_channel_contract.dart';
import 'package:excellent_calendar/boundary_adapters/dart_method_channel/method_channel_refresh_token_secure_store.dart';
import 'package:excellent_calendar/native_contract/auth/store_refresh_token_request_dto.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel(NativeMethodChannelNames.native);
  final store = MethodChannelRefreshTokenSecureStore();

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  Map<String, Object?> success(Object data) => {
    'ok': true,
    'data': data,
    'error': null,
    'contract_version': 2,
    'request_id': 'auth-test',
  };

  test('store sends the exact contract payload', () async {
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          return success({'performed': true, 'message': null});
        });
    final result = await store.store(
      StoreRefreshTokenRequestDto(
        refreshToken: 'opaque-refresh-token-value-at-least-32-characters',
        sessionId: '62732653-c76a-40e7-bf72-bccabb54f06a',
        expiresAt: DateTime.utc(2026, 8, 31, 1),
      ),
    );
    expect(calls.single.method, NativeAuthMethods.refreshTokenStore);
    expect(calls.single.arguments, {
      'refresh_token': 'opaque-refresh-token-value-at-least-32-characters',
      'session_id': '62732653-c76a-40e7-bf72-bccabb54f06a',
      // 重编码保留精度：DateTime.utc 的 toIso8601String 补 .000。
      'expires_at': '2026-08-31T01:00:00.000Z',
    });
    expect(result.result.ok, isTrue);
    expect(result.result.data!.performed, isTrue);
  });

  test('read parses the sensitive record', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          expect(call.method, NativeAuthMethods.refreshTokenRead);
          expect(call.arguments, <String, dynamic>{});
          return success({
            'refresh_token':
                'opaque-refresh-token-value-at-least-32-characters',
            'session_id': '62732653-c76a-40e7-bf72-bccabb54f06a',
            'expires_at': '2026-08-31T01:00:00Z',
          });
        });
    final result = await store.read();
    expect(result.result.ok, isTrue);
    expect(
      result.result.data!.refreshToken,
      'opaque-refresh-token-value-at-least-32-characters',
    );
  });

  test('read surfaces SECURE_TOKEN_NOT_FOUND as a typed failure', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          return {
            'ok': false,
            'data': null,
            'error': {
              'code': 'SECURE_TOKEN_NOT_FOUND',
              'message': 'No Refresh Token record exists.',
              'details': null,
              'retryable': false,
            },
            'contract_version': 2,
            'request_id': 'auth-test',
          };
        });
    final result = await store.read();
    expect(result.result.ok, isFalse);
    expect(result.errorCode, 'SECURE_TOKEN_NOT_FOUND');
  });

  test('delete and exists map to the declared methods', () async {
    final calls = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call.method);
          if (call.method == NativeAuthMethods.refreshTokenExists) {
            return success({'exists': true});
          }
          return success({'performed': true, 'message': null});
        });
    final deleted = await store.delete();
    expect(deleted.result.ok, isTrue);
    final exists = await store.exists();
    expect(exists.result.data!.exists, isTrue);
    expect(calls, [
      NativeAuthMethods.refreshTokenDelete,
      NativeAuthMethods.refreshTokenExists,
    ]);
  });

  test('malformed native payload becomes a contract failure', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          return {
            'ok': true,
            'data': {'exists': 'not-a-bool'},
            'error': null,
            'contract_version': 2,
            'request_id': 'auth-test',
          };
        });
    final result = await store.exists();
    expect(result.result.ok, isFalse);
    expect(result.errorCode, 'CONTRACT_VALIDATION_FAILED');
  });
}
