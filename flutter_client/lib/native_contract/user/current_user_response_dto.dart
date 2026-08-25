import 'user_account_response_dto.dart';
import 'user_preferences_response_dto.dart';
import 'user_profile_response_dto.dart';
import '../shared/contract_value.dart';

/// Authenticated-user aggregate. Never contains credentials.
class CurrentUserResponseDto {
  const CurrentUserResponseDto({
    required this.account,
    required this.profile,
    required this.preferences,
  });

  final UserAccountResponseDto account;
  final UserProfileResponseDto profile;
  final UserPreferencesResponseDto preferences;

  factory CurrentUserResponseDto.fromJson(Map<String, dynamic> json) {
    ContractValue.requireExactKeys(json, {
      'account',
      'profile',
      'preferences',
    }, 'CurrentUserResponse');
    final account = json['account'];
    final profile = json['profile'];
    final preferences = json['preferences'];
    if (account is! Map<String, dynamic> ||
        profile is! Map<String, dynamic> ||
        preferences is! Map<String, dynamic>) {
      throw const FormatException(
        'CurrentUserResponse.account/profile/preferences must be objects.',
      );
    }
    return CurrentUserResponseDto(
      account: UserAccountResponseDto.fromJson(account),
      profile: UserProfileResponseDto.fromJson(profile),
      preferences: UserPreferencesResponseDto.fromJson(preferences),
    );
  }

  Map<String, dynamic> toJson() => {
    'account': account.toJson(),
    'profile': profile.toJson(),
    'preferences': preferences.toJson(),
  };
}
