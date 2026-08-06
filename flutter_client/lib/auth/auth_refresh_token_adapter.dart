import 'package:flutter/services.dart';

import '../native_contract/common/native_result_dto.dart';
import '../native_contract/shared/native_invocation.dart';
import '../native_contract/shared/native_json_normalizer.dart';

/// DTO for the response from `auth.refresh_token.read`.
class SecureRefreshTokenRecord {
  const SecureRefreshTokenRecord({
    required this.refreshToken,
    required this.sessionId,
    required this.expiresAt,
  });

  final String refreshToken;
  final String sessionId;
  final String expiresAt;
}

/// DTO for the response from `auth.refresh_token.exists`.
class RefreshTokenPresence {
  const RefreshTokenPresence({required this.exists});

  final bool exists;
}

/// Adapter for the `auth.refresh_token.*` MethodChannel calls.
///
/// These methods talk to Android secure storage (Keystore).
/// The Refresh Token must never be logged or persisted in Flutter storage.
class AuthRefreshTokenAdapter {
  static const _channel = MethodChannel('excellent_calendar/native');

  /// Store the Refresh Token in Android secure storage.
  Future<NativeInvocation<OperationResponse>> store({
    required String refreshToken,
    required String sessionId,
    required String expiresAt,
  }) async {
    return _invoke(
      method: 'auth.refresh_token.store',
      arguments: {
        'refresh_token': refreshToken,
        'session_id': sessionId,
        'expires_at': expiresAt,
      },
      parseData: (raw) => OperationResponse.fromJson(
        NativeJsonNormalizer.normalizeMap(raw),
      ),
    );
  }

  /// Read the Refresh Token from Android secure storage.
  ///
  /// The returned token must only be held in memory for the duration of
  /// the refresh request and cleared immediately after.
  Future<NativeInvocation<SecureRefreshTokenRecord>> read() async {
    return _invoke(
      method: 'auth.refresh_token.read',
      arguments: {},
      parseData: (raw) {
        final map = NativeJsonNormalizer.normalizeMap(raw);
        return SecureRefreshTokenRecord(
          refreshToken: map['refresh_token'] as String,
          sessionId: map['session_id'] as String,
          expiresAt: map['expires_at'] as String,
        );
      },
    );
  }

  /// Delete the Refresh Token from Android secure storage.
  Future<NativeInvocation<OperationResponse>> delete() async {
    return _invoke(
      method: 'auth.refresh_token.delete',
      arguments: {},
      parseData: (raw) => OperationResponse.fromJson(
        NativeJsonNormalizer.normalizeMap(raw),
      ),
    );
  }

  /// Check whether a Refresh Token exists in Android secure storage.
  Future<NativeInvocation<RefreshTokenPresence>> exists() async {
    return _invoke(
      method: 'auth.refresh_token.exists',
      arguments: {},
      parseData: (raw) {
        final map = NativeJsonNormalizer.normalizeMap(raw);
        return RefreshTokenPresence(exists: map['exists'] as bool);
      },
    );
  }

  Future<NativeInvocation<T>> _invoke<T>({
    required String method,
    required Map<String, dynamic> arguments,
    required T Function(Object? rawData) parseData,
  }) async {
    try {
      final raw = await _channel.invokeMethod<Object?>(method, arguments);
      final rawResponse = NativeJsonNormalizer.normalizeMap(raw);
      final result = NativeResultDto<T>.fromJson(rawResponse, parseData);
      return NativeInvocation<T>(
        rawResponse: rawResponse,
        result: result,
        isNativeResult: true,
      );
    } on PlatformException catch (error) {
      return _localFailure(
        code: 'NATIVE_INTERNAL_ERROR',
        message: error.message ?? 'MethodChannel PlatformException',
      );
    } on MissingPluginException catch (error) {
      return _localFailure(
        code: 'NATIVE_INTERNAL_ERROR',
        message: error.message ?? 'MethodChannel plugin not registered',
      );
    }
  }

  NativeInvocation<T> _localFailure<T>({
    required String code,
    required String message,
  }) {
    final rawResponse = <String, dynamic>{
      'flutter_diagnostic': true,
      'native_result_available': false,
      'error': {'code': code, 'message': message, 'retryable': false},
    };
    return NativeInvocation<T>(
      rawResponse: rawResponse,
      result: NativeResultDto.localFailure<T>(
        code: code,
        message: message,
      ),
      isNativeResult: false,
    );
  }
}

/// DTO for `operation_response.schema.json`.
class OperationResponse {
  const OperationResponse({required this.performed, this.message});

  factory OperationResponse.fromJson(Map<String, dynamic> json) {
    return OperationResponse(
      performed: json['performed'] as bool,
      message: json['message'] as String?,
    );
  }

  final bool performed;
  final String? message;
}