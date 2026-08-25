import 'current_user_response_dto.dart';
import '../shared/contract_value.dart';

/// Flutter ordinary-cache format v1. Session credentials are forbidden.
class CachedCurrentUserDto {
  const CachedCurrentUserDto({
    required this.currentUser,
    required this.cachedAt,
  });

  final CurrentUserResponseDto currentUser;
  final DateTime cachedAt;

  static const storageFormatVersion = 1;

  factory CachedCurrentUserDto.fromJson(Map<String, dynamic> json) {
    ContractValue.requireExactKeys(json, {
      'storage_format_version',
      'current_user',
      'cached_at',
    }, 'CachedCurrentUser');
    final version = json['storage_format_version'];
    if (version != storageFormatVersion) {
      throw FormatException(
        'CachedCurrentUser.storage_format_version must be $storageFormatVersion.',
      );
    }
    final currentUser = json['current_user'];
    if (currentUser is! Map<String, dynamic>) {
      throw const FormatException(
        'CachedCurrentUser.current_user must be object.',
      );
    }
    return CachedCurrentUserDto(
      currentUser: CurrentUserResponseDto.fromJson(currentUser),
      cachedAt: ContractValue.utcDateTime(
        json,
        'cached_at',
        'CachedCurrentUser',
      ),
    );
  }

  Map<String, dynamic> toJson() => {
    'storage_format_version': storageFormatVersion,
    'current_user': currentUser.toJson(),
    'cached_at': ContractValue.formatUtcDateTime(
      cachedAt,
      field: 'CachedCurrentUser.cached_at',
    ),
  };
}
