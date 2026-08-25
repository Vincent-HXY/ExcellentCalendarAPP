enum NotificationPermissionStatus {
  granted('granted'),
  denied('denied'),
  notRequired('not_required'),
  permanentlyDenied('permanently_denied'),
  unknown('unknown');

  const NotificationPermissionStatus(this.wireValue);
  final String wireValue;

  static NotificationPermissionStatus fromWireValue(String value) =>
      values.firstWhere(
        (item) => item.wireValue == value,
        orElse: () => throw FormatException(
          'Unknown NotificationPermissionStatus: $value',
        ),
      );
}

enum ExactAlarmPermissionStatus {
  granted('granted'),
  denied('denied'),
  notRequired('not_required'),
  unknown('unknown');

  const ExactAlarmPermissionStatus(this.wireValue);
  final String wireValue;

  static ExactAlarmPermissionStatus fromWireValue(String value) =>
      values.firstWhere(
        (item) => item.wireValue == value,
        orElse: () =>
            throw FormatException('Unknown ExactAlarmPermissionStatus: $value'),
      );
}

enum NotificationPermissionRequestSource {
  appStartup('app_startup'),
  settingsPage('settings_page'),
  reminderCreation('reminder_creation'),
  manualRetry('manual_retry');

  const NotificationPermissionRequestSource(this.wireValue);
  final String wireValue;
}

enum NotificationSettingsTarget {
  notification('notification'),
  exactAlarm('exact_alarm'),
  application('application'),
  ringChannel('ring_channel'),
  fullScreenIntent('full_screen_intent');

  const NotificationSettingsTarget(this.wireValue);
  final String wireValue;
}

enum NotificationTargetType {
  event('event'),
  habit('habit'),
  anniversary('anniversary'),
  reminderRecoveryBatch('reminder_recovery_batch');

  const NotificationTargetType(this.wireValue);
  final String wireValue;

  static NotificationTargetType fromWireValue(String value) =>
      values.firstWhere(
        (item) => item.wireValue == value,
        orElse: () =>
            throw FormatException('Unknown Notification target_type: $value'),
      );
}

enum NotificationKind {
  reminder('reminder'),
  recoverySummary('recovery_summary'),
  anniversaryCatchUp('anniversary_catch_up');

  const NotificationKind(this.wireValue);
  final String wireValue;

  static NotificationKind fromWireValue(String value) => values.firstWhere(
    (item) => item.wireValue == value,
    orElse: () => throw FormatException('Unknown Notification kind: $value'),
  );
}
