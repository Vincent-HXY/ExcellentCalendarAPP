import '../shared/contract_value.dart';

/// Enumeration-resistant response returned for any submitted email.
class PasswordResetDispatchResponseDto {
  const PasswordResetDispatchResponseDto({required this.resendAvailableAt});

  final DateTime resendAvailableAt;

  factory PasswordResetDispatchResponseDto.fromJson(Map<String, dynamic> json) {
    ContractValue.requireExactKeys(json, {
      'accepted',
      'resend_available_at',
    }, 'PasswordResetDispatchResponse');
    if (json['accepted'] != true) {
      throw const FormatException(
        'PasswordResetDispatchResponse.accepted must be true.',
      );
    }
    return PasswordResetDispatchResponseDto(
      resendAvailableAt: ContractValue.utcDateTime(
        json,
        'resend_available_at',
        'PasswordResetDispatchResponse',
      ),
    );
  }
}
