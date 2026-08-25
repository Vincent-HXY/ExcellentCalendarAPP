import 'dart:convert';

import 'package:dio/dio.dart';

import '../../native_contract/common/api_error_codes.dart';
import '../../native_contract/common/api_error_dto.dart';
import '../../native_contract/common/api_result_dto.dart';
import '../../native_contract/shared/native_json_normalizer.dart';
import 'backend_api_config.dart';
import 'backend_api_endpoints.dart';
import 'backend_api_errors.dart';

/// Unified Flutter → Backend HTTP client.
///
/// Owns baseUrl/timeouts, ApiResult v1 parsing, Idempotency-Key support,
/// Authorization header attachment, and the single-retry-after-refresh rule.
/// Raw maps never leave this class.
class DioBackendApiClient {
  DioBackendApiClient({
    required BackendApiConfig config,
    required String? Function() accessTokenProvider,
    required Future<void> Function() refreshSession,
    required void Function() onSessionEnded,
    Dio? dio,
  }) : _accessTokenProvider = accessTokenProvider,
       _refreshSession = refreshSession,
       _onSessionEnded = onSessionEnded,
       _dio =
           dio ??
           Dio(
             BaseOptions(
               baseUrl: config.baseUrl + config.basePath,
               connectTimeout: config.connectTimeout,
               sendTimeout: config.sendTimeout,
               receiveTimeout: config.receiveTimeout,
               contentType: Headers.jsonContentType,
               validateStatus: (_) => true,
             ),
           );

  final String? Function() _accessTokenProvider;
  final Future<void> Function() _refreshSession;
  final void Function() _onSessionEnded;
  final Dio _dio;

  Future<T> send<T>({
    required BackendApiEndpoint endpoint,
    Map<String, dynamic>? data,
    required T Function(Object? rawData) parseData,
    String? idempotencyKey,
  }) async {
    var attempt = 0;
    while (true) {
      final outcome = await _attempt<T>(
        endpoint: endpoint,
        data: data,
        parseData: parseData,
        idempotencyKey: idempotencyKey,
      );
      if (outcome is _AttemptSuccess<T>) {
        return outcome.value;
      }
      final failure = outcome as _AttemptFailure<T>;
      final apiError = failure.apiError;
      final shouldRefresh =
          attempt == 0 &&
          apiError != null &&
          endpoint.requiresAuth &&
          ApiErrorCodes.isAccessTokenFailure(apiError.code);
      if (!shouldRefresh) {
        throw failure.exception;
      }
      try {
        await _refreshSession();
      } catch (refreshError) {
        if (refreshError is SessionEndedException ||
            refreshError is BackendTransportException ||
            refreshError is BackendContractException) {
          rethrow;
        }
        throw BackendTransportException(BackendTransportKind.network);
      }
      attempt += 1;
      final retried = await _attempt<T>(
        endpoint: endpoint,
        data: data,
        parseData: parseData,
        idempotencyKey: idempotencyKey,
      );
      if (retried is _AttemptSuccess<T>) {
        return retried.value;
      }
      final retriedFailure = retried as _AttemptFailure<T>;
      final retriedError = retriedFailure.apiError;
      if (retriedError != null &&
          ApiErrorCodes.isAccessTokenFailure(retriedError.code)) {
        _onSessionEnded();
        throw SessionEndedException(retriedError.code);
      }
      throw retriedFailure.exception;
    }
  }

  Future<_Attempt<T>> _attempt<T>({
    required BackendApiEndpoint endpoint,
    Map<String, dynamic>? data,
    required T Function(Object? rawData) parseData,
    String? idempotencyKey,
  }) async {
    final headers = <String, dynamic>{'Idempotency-Key': ?idempotencyKey};
    if (endpoint.requiresAuth) {
      final token = _accessTokenProvider();
      if (token != null) {
        headers['Authorization'] = 'Bearer $token';
      }
    }
    final options = Options(method: endpoint.method, headers: headers);
    try {
      final response = await _dio.request<Object?>(
        endpoint.path,
        data: data,
        options: options,
      );
      return _parseResponse(response, parseData);
    } on DioException catch (error) {
      return _Attempt.failure(_mapTransport(error));
    }
  }

  _Attempt<T> _parseResponse<T>(
    Response<Object?> response,
    T Function(Object? rawData) parseData,
  ) {
    // Bare non-envelope 5xx means the gateway/proxy itself failed; classify it
    // as a server transport failure so the UI shows "服务器暂时不可用" and it
    // stays retryable, instead of a misleading contract error. 4xx without an
    // envelope is still a protocol violation → contract failure.
    final status = response.statusCode ?? 0;
    final serverDown = status >= 500;

    Object? rawBody;
    try {
      rawBody = response.data is String
          ? jsonDecode(response.data as String)
          : response.data;
    } catch (_) {
      return _Attempt.failure(
        serverDown
            ? const BackendTransportException(BackendTransportKind.server)
            : const BackendContractException(
                'Response body is not valid JSON.',
              ),
      );
    }
    if (rawBody is! Map<String, dynamic>) {
      return _Attempt.failure(
        serverDown
            ? const BackendTransportException(BackendTransportKind.server)
            : const BackendContractException(
                'Response body must be a JSON object.',
              ),
      );
    }
    final normalized = NativeJsonNormalizer.normalizeMap(rawBody);
    final ApiResultDto<T> result;
    try {
      result = ApiResultDto<T>.fromJson(normalized, parseData);
    } on FormatException catch (error) {
      // 合法 JSON 但不是 ApiResult 信封：5xx 归服务器故障，其余仍是契约错误。
      return _Attempt.failure(
        serverDown
            ? const BackendTransportException(BackendTransportKind.server)
            : BackendContractException('Malformed ApiResult: ${error.message}'),
      );
    }
    if (result.ok) {
      return _Attempt.success(result.data as T);
    }
    final apiError = result.error!;
    return _Attempt.failure(
      BackendApiException(error: apiError, requestId: result.requestId),
      apiError,
    );
  }

  Object _mapTransport(DioException error) {
    switch (error.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.transformTimeout:
        return const BackendTransportException(BackendTransportKind.timeout);
      case DioExceptionType.connectionError:
      case DioExceptionType.unknown:
        // 含裸非 JSON 响应体：dio 在此抛 unknown 且不携带响应状态码，只能
        // 归为通用网络故障（仍属 transport，绝非业务错误码）。JSON 对象体的
        // 非 2xx 会正常进入 _parseResponse 由状态码区分 server/contract。
        return BackendTransportException(
          BackendTransportKind.network,
          error.message,
        );
      case DioExceptionType.badCertificate:
        return const BackendTransportException(BackendTransportKind.network);
      case DioExceptionType.badResponse:
        // 防御性分支：默认 Dio 的 validateStatus 恒为 true，不会抛
        // badResponse；仅当调用方注入自定义 Dio（改 validateStatus）时才可达。
        final status = error.response?.statusCode ?? 0;
        if (status >= 500) {
          return const BackendTransportException(BackendTransportKind.server);
        }
        return const BackendContractException(
          'Non-envelope HTTP failure response.',
        );
      case DioExceptionType.cancel:
        return const BackendTransportException(BackendTransportKind.network);
    }
  }
}

sealed class _Attempt<T> {
  const _Attempt();

  factory _Attempt.success(T value) => _AttemptSuccess<T>(value);

  factory _Attempt.failure(Object exception, [ApiErrorDto? apiError]) =>
      _AttemptFailure<T>(exception, apiError);
}

class _AttemptSuccess<T> extends _Attempt<T> {
  const _AttemptSuccess(this.value);

  final T value;
}

class _AttemptFailure<T> extends _Attempt<T> {
  const _AttemptFailure(this.exception, [this.apiError]);

  final Object exception;
  final ApiErrorDto? apiError;
}
