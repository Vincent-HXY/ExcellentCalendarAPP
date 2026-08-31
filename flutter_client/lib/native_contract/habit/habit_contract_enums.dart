enum HabitLifecycleStatusContract {
  upcoming('upcoming'),
  active('active'),
  completed('completed'),
  endedEarly('ended_early');

  const HabitLifecycleStatusContract(this.wireValue);
  final String wireValue;

  static HabitLifecycleStatusContract fromWireValue(String value) =>
      values.where((item) => item.wireValue == value).firstOrNull ??
      (throw FormatException('Unknown Habit lifecycle status: $value'));
}

enum HabitDailyStatusContract {
  upcoming('upcoming'),
  absent('absent'),
  partial('partial'),
  done('done'),
  skipped('skipped'),
  missed('missed');

  const HabitDailyStatusContract(this.wireValue);
  final String wireValue;

  static HabitDailyStatusContract fromWireValue(String value) =>
      values.where((item) => item.wireValue == value).firstOrNull ??
      (throw FormatException('Unknown Habit daily status: $value'));
}

enum HabitCheckInStatusContract {
  done('done'),
  partial('partial'),
  skipped('skipped');

  const HabitCheckInStatusContract(this.wireValue);
  final String wireValue;

  static HabitCheckInStatusContract fromWireValue(String value) =>
      values.where((item) => item.wireValue == value).firstOrNull ??
      (throw FormatException('Unknown Habit check-in status: $value'));
}

enum HabitCheckInSourceContract {
  manual('manual'),
  notificationAction('notification_action');

  const HabitCheckInSourceContract(this.wireValue);
  final String wireValue;

  static HabitCheckInSourceContract fromWireValue(String value) =>
      values.where((item) => item.wireValue == value).firstOrNull ??
      (throw FormatException('Unknown Habit check-in source: $value'));
}

enum HabitScheduleStatusContract {
  notRequired('not_required'),
  scheduledExact('scheduled_exact'),
  scheduledApproximate('scheduled_approximate'),
  pendingPermission('pending_permission'),
  pendingReconciliation('pending_reconciliation');

  const HabitScheduleStatusContract(this.wireValue);
  final String wireValue;

  static HabitScheduleStatusContract fromWireValue(String value) =>
      values.where((item) => item.wireValue == value).firstOrNull ??
      (throw FormatException('Unknown Habit schedule status: $value'));
}

enum HabitNotificationPermissionContract {
  granted('granted'),
  denied('denied'),
  notRequired('not_required'),
  permanentlyDenied('permanently_denied'),
  unknown('unknown');

  const HabitNotificationPermissionContract(this.wireValue);
  final String wireValue;

  static HabitNotificationPermissionContract fromWireValue(String value) =>
      values.where((item) => item.wireValue == value).firstOrNull ??
      (throw FormatException('Unknown notification permission: $value'));
}

enum HabitExactAlarmPermissionContract {
  granted('granted'),
  denied('denied'),
  notRequired('not_required'),
  unknown('unknown');

  const HabitExactAlarmPermissionContract(this.wireValue);
  final String wireValue;

  static HabitExactAlarmPermissionContract fromWireValue(String value) =>
      values.where((item) => item.wireValue == value).firstOrNull ??
      (throw FormatException('Unknown exact-alarm permission: $value'));
}

enum HabitScheduleDegradationReasonContract {
  notificationPermissionUnavailable('notification_permission_unavailable'),
  exactAlarmPermissionUnavailable('exact_alarm_permission_unavailable'),
  schedulerRetryRequired('scheduler_retry_required');

  const HabitScheduleDegradationReasonContract(this.wireValue);
  final String wireValue;

  static HabitScheduleDegradationReasonContract fromWireValue(String value) =>
      values.where((item) => item.wireValue == value).firstOrNull ??
      (throw FormatException('Unknown Habit degradation reason: $value'));
}
