import 'dart:async';

import 'package:excellent_calendar/gateway_interfaces/refresh_token_secure_store_gateway.dart';
import 'package:excellent_calendar/native_contract/auth/refresh_token_presence_response_dto.dart';
import 'package:excellent_calendar/native_contract/auth/secure_refresh_token_record_response_dto.dart';
import 'package:excellent_calendar/native_contract/auth/store_refresh_token_request_dto.dart';
import 'package:excellent_calendar/native_contract/common/operation_response_dto.dart';
import 'package:excellent_calendar/native_contract/shared/native_invocation.dart';
import 'package:excellent_calendar/native_contract/common/native_result_dto.dart';

/// In-memory RefreshTokenSecureStoreGateway.
class FakeRefreshTokenStore implements RefreshTokenSecureStoreGateway {
  SecureRefreshTokenRecordResponseDto? record;
  bool failStore = false;
  bool failExists = false;
  int storeCalls = 0;
  int deleteCalls = 0;
  int readCalls = 0;
  int existsCalls = 0;

  /// When set, store() suspends on this gate before writing the record,
  /// letting tests interleave logout in the middle of a token write.
  Completer<void>? storeGate;

  @override
  Future<NativeInvocation<OperationResponseDto>> store(
    StoreRefreshTokenRequestDto request,
  ) async {
    storeCalls += 1;
    if (failStore) {
      return NativeInvocation<OperationResponseDto>(
        rawResponse: const {},
        result: NativeResultDto.localFailure(
          code: 'SECURE_TOKEN_STORAGE_FAILED',
          message:
              'Android secure storage could not persist the Refresh Token.',
          retryable: true,
        ),
        isNativeResult: false,
      );
    }
    final gate = storeGate;
    if (gate != null) {
      await gate.future;
    }
    record = SecureRefreshTokenRecordResponseDto(
      refreshToken: request.refreshToken,
      sessionId: request.sessionId,
      expiresAt: request.expiresAt,
    );
    return _success(const OperationResponseDto(performed: true));
  }

  @override
  Future<NativeInvocation<SecureRefreshTokenRecordResponseDto>> read() async {
    readCalls += 1;
    final current = record;
    if (current == null) {
      return NativeInvocation<SecureRefreshTokenRecordResponseDto>(
        rawResponse: const {},
        result: NativeResultDto.localFailure(
          code: 'SECURE_TOKEN_NOT_FOUND',
          message: 'No Refresh Token record exists.',
        ),
        isNativeResult: false,
      );
    }
    return _success(current);
  }

  int deleteFailuresRemaining = 0;

  @override
  Future<NativeInvocation<OperationResponseDto>> delete() async {
    deleteCalls += 1;
    if (deleteFailuresRemaining > 0) {
      deleteFailuresRemaining -= 1;
      return NativeInvocation<OperationResponseDto>(
        rawResponse: const {},
        result: NativeResultDto.localFailure(
          code: 'SECURE_TOKEN_STORAGE_FAILED',
          message: 'Secure store delete failed.',
          retryable: true,
        ),
        isNativeResult: false,
      );
    }
    record = null;
    return _success(const OperationResponseDto(performed: true));
  }

  @override
  Future<NativeInvocation<RefreshTokenPresenceResponseDto>> exists() async {
    existsCalls += 1;
    if (failExists) {
      return NativeInvocation<RefreshTokenPresenceResponseDto>(
        rawResponse: const {},
        result: NativeResultDto.localFailure(
          code: 'SECURE_TOKEN_STORAGE_FAILED',
          message: 'Android secure storage could not be queried.',
          retryable: true,
        ),
        isNativeResult: false,
      );
    }
    return _success(RefreshTokenPresenceResponseDto(exists: record != null));
  }

  NativeInvocation<T> _success<T>(T data) => NativeInvocation<T>(
    rawResponse: const {},
    result: NativeResultDto<T>(
      ok: true,
      data: data,
      error: null,
      contractVersion: 2,
      requestId: 'fake',
    ),
    isNativeResult: true,
  );
}
