import '../../native_contract/common/api_error_dto.dart';

/// A well-formed backend business failure (ApiResult with ok=false).
class BackendApiException implements Exception {
  const BackendApiException({required this.error, required this.requestId});

  final ApiErrorDto error;
  final String requestId;

  String get code => error.code;
  bool get retryable => error.retryable;

  @override
  String toString() =>
      'BackendApiException(code: $code, request_id: $requestId)';
}

enum BackendTransportKind { network, timeout, server }

/// Connection-level failure: offline, DNS, timeouts, HTTP 5xx without a
/// parseable envelope. Distinct from backend business errors.
class BackendTransportException implements Exception {
  const BackendTransportException(this.kind, [this.message]);

  final BackendTransportKind kind;
  final String? message;

  bool get isNetwork => kind == BackendTransportKind.network;
  bool get isTimeout => kind == BackendTransportKind.timeout;

  @override
  String toString() => 'BackendTransportException(${kind.name})';
}

/// The response could not be read as ApiResult v1 at all.
class BackendContractException implements Exception {
  const BackendContractException(this.message);

  final String message;

  @override
  String toString() => 'BackendContractException: $message';
}

/// The session can no longer be recovered: refresh failed or the retried
/// request still failed. The session state must be cleared.
class SessionEndedException implements Exception {
  const SessionEndedException([this.reason]);

  final String? reason;

  @override
  String toString() => 'SessionEndedException: ${reason ?? 'session ended'}';
}
