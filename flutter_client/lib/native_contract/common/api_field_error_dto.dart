import '../shared/contract_json_object.dart';

/// Backend API v1 per-field validation error.
class ApiFieldErrorDto {
  const ApiFieldErrorDto({
    required this.field,
    required this.code,
    required this.message,
  });

  final String field;
  final String code;
  final String message;

  factory ApiFieldErrorDto.fromJson(Map<String, dynamic> json) {
    ContractJsonObject.rejectUnknownKeys(json, {
      'field',
      'code',
      'message',
    }, 'ApiFieldError');
    ContractJsonObject.requireKeys(json, {
      'field',
      'code',
      'message',
    }, 'ApiFieldError');

    final field = json['field'];
    final code = json['code'];
    final message = json['message'];

    if (field is! String || field.isEmpty || field.length > 128) {
      throw const FormatException(
        'ApiFieldError.field must be a 1..128 string.',
      );
    }
    if (code is! String || !RegExp(r'^[A-Z][A-Z0-9_]*$').hasMatch(code)) {
      throw const FormatException(
        'ApiFieldError.code must be SCREAMING_SNAKE.',
      );
    }
    if (message is! String || message.isEmpty || message.length > 256) {
      throw const FormatException(
        'ApiFieldError.message must be a 1..256 string.',
      );
    }
    return ApiFieldErrorDto(field: field, code: code, message: message);
  }
}
