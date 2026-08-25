import 'user_settings_dto.dart';
import '../shared/contract_value.dart';

/// Last-write-wins partial update for non-security profile fields.
class UpdateCurrentUserRequestDto {
  const UpdateCurrentUserRequestDto({
    this.username,
    this.displayName,
    this.locale,
    this.timezone,
    this.defaultReminderMethods,
    this.settings,
  });

  final String? username;
  final String? displayName;
  final String? locale;
  final String? timezone;
  final List<String>? defaultReminderMethods;
  final UserSettingsDto? settings;

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{};
    if (username != null) json['username'] = username;
    if (displayName != null) json['display_name'] = displayName;
    if (locale != null) json['locale'] = locale;
    if (timezone != null) json['timezone'] = timezone;
    if (defaultReminderMethods != null) {
      json['default_reminder_methods'] = defaultReminderMethods;
    }
    if (settings != null) json['settings'] = settings!.toJson();
    if (json.isEmpty) {
      throw const FormatException(
        'UpdateCurrentUserRequest must update at least one field.',
      );
    }
    return json;
  }

  static void validateFieldValues(Map<String, dynamic> json) {
    ContractValue.requireExactKeys(json, {
      'username',
      'display_name',
      'locale',
      'timezone',
      'default_reminder_methods',
      'settings',
    }, 'UpdateCurrentUserRequest');
  }
}
