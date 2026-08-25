enum AnniversaryCalendarTypeContract {
  solar('solar'),
  lunar('lunar');

  const AnniversaryCalendarTypeContract(this.wireValue);
  final String wireValue;

  static AnniversaryCalendarTypeContract fromWireValue(String value) =>
      values.firstWhere(
        (item) => item.wireValue == value,
        orElse: () =>
            throw FormatException('Unknown Anniversary calendar_type: $value'),
      );
}

enum AnniversaryImportanceContract {
  unimportantNotUrgent('unimportant_noturgent'),
  importantNotUrgent('important_noturgent'),
  unimportantUrgent('unimportant_urgent'),
  importantUrgent('important_urgent');

  const AnniversaryImportanceContract(this.wireValue);
  final String wireValue;

  static AnniversaryImportanceContract fromWireValue(String value) =>
      values.firstWhere(
        (item) => item.wireValue == value,
        orElse: () =>
            throw FormatException('Unknown Anniversary importance: $value'),
      );
}

enum AnniversaryCountdownRelationContract {
  remaining('remaining'),
  elapsed('elapsed'),
  today('today');

  const AnniversaryCountdownRelationContract(this.wireValue);
  final String wireValue;

  static AnniversaryCountdownRelationContract fromWireValue(String value) =>
      values.firstWhere(
        (item) => item.wireValue == value,
        orElse: () => throw FormatException(
          'Unknown Anniversary countdown relation: $value',
        ),
      );
}

enum AnniversarySortByContract {
  targetOccurrenceDate('target_occurrence_date'),
  countdownDays('countdown_days');

  const AnniversarySortByContract(this.wireValue);
  final String wireValue;
}

enum AnniversarySortDirectionContract {
  ascending('asc'),
  descending('desc');

  const AnniversarySortDirectionContract(this.wireValue);
  final String wireValue;
}

enum AnniversaryReminderTimezoneModeContract {
  followDevice('follow_device');

  const AnniversaryReminderTimezoneModeContract(this.wireValue);
  final String wireValue;
}

enum AnniversaryScheduleStatusContract {
  notRequired('not_required'),
  scheduledExact('scheduled_exact'),
  scheduledApproximate('scheduled_approximate'),
  pendingPermission('pending_permission'),
  pendingReconciliation('pending_reconciliation');

  const AnniversaryScheduleStatusContract(this.wireValue);
  final String wireValue;

  static AnniversaryScheduleStatusContract fromWireValue(String value) =>
      values.firstWhere(
        (item) => item.wireValue == value,
        orElse: () => throw FormatException(
          'Unknown Anniversary schedule status: $value',
        ),
      );
}

enum AnniversaryScheduleDegradationReasonContract {
  notificationPermissionUnavailable('notification_permission_unavailable'),
  exactAlarmPermissionUnavailable('exact_alarm_permission_unavailable'),
  schedulerRetryRequired('scheduler_retry_required');

  const AnniversaryScheduleDegradationReasonContract(this.wireValue);
  final String wireValue;

  static AnniversaryScheduleDegradationReasonContract fromWireValue(
    String value,
  ) => values.firstWhere(
    (item) => item.wireValue == value,
    orElse: () => throw FormatException(
      'Unknown Anniversary schedule degradation reason: $value',
    ),
  );
}
