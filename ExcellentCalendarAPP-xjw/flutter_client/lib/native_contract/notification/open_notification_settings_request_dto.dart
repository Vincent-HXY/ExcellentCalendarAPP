import 'notification_contract_enums.dart';

class OpenNotificationSettingsRequestDto {
  const OpenNotificationSettingsRequestDto({required this.settingsTarget});

  final NotificationSettingsTarget settingsTarget;

  Map<String, dynamic> toJson() => {
    'settings_target': settingsTarget.wireValue,
  };
}
