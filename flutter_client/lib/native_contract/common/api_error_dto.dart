import 'api_error_codes.dart';
import 'api_error_context_dto.dart';
import 'api_field_error_dto.dart';
import '../shared/contract_json_object.dart';

/// Backend API v1 safe error. Never contains stack traces or secrets.
class ApiErrorDto {
  const ApiErrorDto({
    required this.code,
    required this.message,
    required this.retryable,
    required this.fieldErrors,
    this.retryAfterSeconds,
    this.context,
  });

  final String code;
  final String message;
  final bool retryable;
  final List<ApiFieldErrorDto> fieldErrors;
  final int? retryAfterSeconds;
  final ApiErrorContextDto? context;

  factory ApiErrorDto.fromJson(Map<String, dynamic> json) {
    ContractJsonObject.rejectUnknownKeys(json, {
      'code',
      'message',
      'retryable',
      'field_errors',
      'retry_after_seconds',
      'context',
    }, 'ApiError');
    ContractJsonObject.requireKeys(json, {
      'code',
      'message',
      'retryable',
      'field_errors',
      'retry_after_seconds',
    }, 'ApiError');

    final code = json['code'];
    final message = json['message'];
    final retryable = json['retryable'];
    final fieldErrors = json['field_errors'];
    final retryAfterSeconds = json['retry_after_seconds'];
    final rawContext = json['context'];

    if (code is! String || !ApiErrorCodes.values.contains(code)) {
      throw FormatException('Unknown ApiError.code: $code');
    }
    if (message is! String || message.isEmpty || message.length > 512) {
      throw const FormatException('ApiError.message must be a 1..512 string.');
    }
    if (retryable is! bool) {
      throw const FormatException('ApiError.retryable must be bool.');
    }
    if (fieldErrors is! List ||
        fieldErrors.any((item) => item is! Map<String, dynamic>)) {
      throw const FormatException('ApiError.field_errors must be an array.');
    }
    if (retryAfterSeconds != null &&
        (retryAfterSeconds is! int || retryAfterSeconds < 0)) {
      throw const FormatException(
        'ApiError.retry_after_seconds must be a non-negative integer or null.',
      );
    }
    ApiErrorContextDto? context;
    if (rawContext != null) {
      if (rawContext is! Map<String, dynamic>) {
        throw const FormatException('ApiError.context must be object or null.');
      }
      context = ApiErrorContextDto.fromJson(rawContext);
    }
    return ApiErrorDto(
      code: code,
      message: message,
      retryable: retryable,
      fieldErrors: List<ApiFieldErrorDto>.unmodifiable(
        fieldErrors.map(
          (item) => ApiFieldErrorDto.fromJson(item as Map<String, dynamic>),
        ),
      ),
      retryAfterSeconds: retryAfterSeconds as int?,
      context: context,
    );
  }
}
