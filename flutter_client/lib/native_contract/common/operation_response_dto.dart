import '../shared/contract_json_object.dart';

class OperationResponseDto {
  const OperationResponseDto({required this.performed, this.message});

  final bool performed;
  final String? message;

  factory OperationResponseDto.fromJson(Map<String, dynamic> json) {
    ContractJsonObject.rejectUnknownKeys(json, {
      'performed',
      'message',
    }, 'OperationResponse');
    ContractJsonObject.requireKeys(json, {'performed'}, 'OperationResponse');
    final performed = json['performed'];
    final message = json['message'];
    if (performed is! bool) {
      throw const FormatException('OperationResponse.performed must be bool.');
    }
    if (message != null && message is! String) {
      throw const FormatException(
        'OperationResponse.message must be string or null.',
      );
    }
    return OperationResponseDto(
      performed: performed,
      message: message as String?,
    );
  }
}
