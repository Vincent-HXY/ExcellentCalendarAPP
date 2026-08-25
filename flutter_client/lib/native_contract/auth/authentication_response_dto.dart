import 'token_pair_response_dto.dart';
import '../user/current_user_response_dto.dart';
import '../shared/contract_value.dart';

/// Complete successful authentication result.
class AuthenticationResponseDto {
  const AuthenticationResponseDto({
    required this.currentUser,
    required this.tokens,
  });

  final CurrentUserResponseDto currentUser;
  final TokenPairResponseDto tokens;

  factory AuthenticationResponseDto.fromJson(Map<String, dynamic> json) {
    ContractValue.requireExactKeys(json, {
      'current_user',
      'tokens',
    }, 'AuthenticationResponse');
    final currentUser = json['current_user'];
    final tokens = json['tokens'];
    if (currentUser is! Map<String, dynamic> ||
        tokens is! Map<String, dynamic>) {
      throw const FormatException(
        'AuthenticationResponse.current_user/tokens must be objects.',
      );
    }
    return AuthenticationResponseDto(
      currentUser: CurrentUserResponseDto.fromJson(currentUser),
      tokens: TokenPairResponseDto.fromJson(tokens),
    );
  }
}
