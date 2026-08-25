import 'user_settings_dto.dart';
import '../shared/contract_value.dart';

/// Stable user preferences returned with the current-user aggregate.
class UserPreferencesResponseDto {
  const UserPreferencesResponseDto({
    required this.userId,
    required this.locale,
    required this.timezone,
    required this.defaultReminderMethods,
    required this.settings,
    required this.createdAt,
    required this.updatedAt,
  });

  final String userId;
  final String locale;
  final String timezone;
  final List<String> defaultReminderMethods;
  final UserSettingsDto settings;
  final DateTime createdAt;
  final DateTime updatedAt;

  static const reminderMethods = {'ring', 'popup', 'wechat'};

  factory UserPreferencesResponseDto.fromJson(Map<String, dynamic> json) {
    ContractValue.requireExactKeys(json, {
      'user_id',
      'locale',
      'timezone',
      'default_reminder_methods',
      'settings',
      'created_at',
      'updated_at',
    }, 'UserPreferencesResponse');

    final locale = json['locale'];
    final timezone = json['timezone'];
    final rawSettings = json['settings'];
    if (locale is! String ||
        !RegExp(r'^[A-Za-z]{2,3}(?:-[A-Za-z0-9]{2,8})*$').hasMatch(locale) ||
        locale.length > 35) {
      throw const FormatException('UserPreferencesResponse.locale is invalid.');
    }
    if (timezone is! String || timezone.isEmpty || timezone.length > 64) {
      throw const FormatException(
        'UserPreferencesResponse.timezone must be a 1..64 string.',
      );
    }
    if (rawSettings is! Map<String, dynamic>) {
      throw const FormatException(
        'UserPreferencesResponse.settings must be object.',
      );
    }
    return UserPreferencesResponseDto(
      userId: ContractValue.uuid(json, 'user_id', 'UserPreferencesResponse'),
      locale: locale,
      timezone: timezone,
      defaultReminderMethods: ContractValue.stringList(
        json,
        'default_reminder_methods',
        'UserPreferencesResponse',
        allowed: reminderMethods,
        unique: true,
      ),
      settings: UserSettingsDto.fromJson(rawSettings),
      createdAt: ContractValue.utcDateTime(
        json,
        'created_at',
        'UserPreferencesResponse',
      ),
      updatedAt: ContractValue.utcDateTime(
        json,
        'updated_at',
        'UserPreferencesResponse',
      ),
    );
  }

  Map<String, dynamic> toJson() => {
    'user_id': userId,
    'locale': locale,
    'timezone': timezone,
    'default_reminder_methods': defaultReminderMethods,
    'settings': settings.toJson(),
    'created_at': ContractValue.formatUtcDateTime(
      createdAt,
      field: 'UserPreferencesResponse.created_at',
    ),
    'updated_at': ContractValue.formatUtcDateTime(
      updatedAt,
      field: 'UserPreferencesResponse.updated_at',
    ),
  };
}
