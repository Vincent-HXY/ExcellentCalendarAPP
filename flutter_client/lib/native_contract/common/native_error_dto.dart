import 'native_error_codes.dart';
import '../shared/contract_json_object.dart';

class NativeErrorDto {
  const NativeErrorDto({
    required this.code,
    required this.message,
    this.details,
    this.retryable = false,
  });

  final String code;
  final String message;
  final Map<String, dynamic>? details;
  final bool retryable;

  factory NativeErrorDto.fromJson(Map<String, dynamic> json) {
    ContractJsonObject.rejectUnknownKeys(json, {
      'code',
      'message',
      'details',
      'retryable',
    }, 'NativeError');
    ContractJsonObject.requireKeys(json, {'code', 'message'}, 'NativeError');

    final code = json['code'];
    final message = json['message'];
    final details = json['details'];
    final retryable = json['retryable'];

    if (code is! String || code.isEmpty) {
      throw const FormatException(
        'NativeError.code must be a non-empty string.',
      );
    }
    if (!NativeErrorCodes.values.contains(code)) {
      throw FormatException('Unknown NativeError.code: $code');
    }
    if (message is! String || message.isEmpty) {
      throw const FormatException(
        'NativeError.message must be a non-empty string.',
      );
    }
    if (details != null && details is! Map<String, dynamic>) {
      throw const FormatException(
        'NativeError.details must be object or null.',
      );
    }
    if (retryable != null && retryable is! bool) {
      throw const FormatException('NativeError.retryable must be bool.');
    }

    return NativeErrorDto(
      code: code,
      message: message,
      details: details as Map<String, dynamic>?,
      retryable: retryable as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'code': code,
      'message': message,
      'details': details,
      'retryable': retryable,
    };
  }
}
