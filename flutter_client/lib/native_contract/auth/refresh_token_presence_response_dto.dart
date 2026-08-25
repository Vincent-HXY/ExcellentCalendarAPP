import '../shared/contract_value.dart';

/// Reports only whether Android secure storage contains a Refresh Token.
class RefreshTokenPresenceResponseDto {
  const RefreshTokenPresenceResponseDto({required this.exists});

  final bool exists;

  factory RefreshTokenPresenceResponseDto.fromJson(Map<String, dynamic> json) {
    ContractValue.requireExactKeys(json, {
      'exists',
    }, 'RefreshTokenPresenceResponse');
    final exists = json['exists'];
    if (exists is! bool) {
      throw const FormatException(
        'RefreshTokenPresenceResponse.exists must be bool.',
      );
    }
    return RefreshTokenPresenceResponseDto(exists: exists);
  }
}
