import 'avatar_info_dto.dart';
import '../shared/contract_value.dart';

/// Public profile data for the authenticated user.
class UserProfileResponseDto {
  const UserProfileResponseDto({
    required this.userId,
    required this.username,
    required this.displayName,
    required this.avatar,
    required this.createdAt,
    required this.updatedAt,
  });

  final String userId;
  final String username;
  final String displayName;
  final AvatarInfoDto? avatar;
  final DateTime createdAt;
  final DateTime updatedAt;

  factory UserProfileResponseDto.fromJson(Map<String, dynamic> json) {
    ContractValue.requireExactKeys(json, {
      'user_id',
      'username',
      'display_name',
      'avatar',
      'created_at',
      'updated_at',
    }, 'UserProfileResponse');

    final username = json['username'];
    final displayName = json['display_name'];
    final rawAvatar = json['avatar'];
    if (username is! String ||
        !RegExp(r'^[a-z0-9_]{3,24}$').hasMatch(username)) {
      throw const FormatException('UserProfileResponse.username is invalid.');
    }
    if (displayName is! String ||
        displayName.isEmpty ||
        displayName.length > 40) {
      throw const FormatException(
        'UserProfileResponse.display_name must be a 1..40 string.',
      );
    }
    AvatarInfoDto? avatar;
    if (rawAvatar != null) {
      if (rawAvatar is! Map<String, dynamic>) {
        throw const FormatException(
          'UserProfileResponse.avatar must be object or null.',
        );
      }
      avatar = AvatarInfoDto.fromJson(rawAvatar);
    }
    return UserProfileResponseDto(
      userId: ContractValue.uuid(json, 'user_id', 'UserProfileResponse'),
      username: username,
      displayName: displayName,
      avatar: avatar,
      createdAt: ContractValue.utcDateTime(
        json,
        'created_at',
        'UserProfileResponse',
      ),
      updatedAt: ContractValue.utcDateTime(
        json,
        'updated_at',
        'UserProfileResponse',
      ),
    );
  }

  Map<String, dynamic> toJson() => {
    'user_id': userId,
    'username': username,
    'display_name': displayName,
    'avatar': avatar?.toJson(),
    'created_at': ContractValue.formatUtcDateTime(
      createdAt,
      field: 'UserProfileResponse.created_at',
    ),
    'updated_at': ContractValue.formatUtcDateTime(
      updatedAt,
      field: 'UserProfileResponse.updated_at',
    ),
  };
}
