class NativeErrorCodes {
  const NativeErrorCodes._();

  static const nativeInternalError = 'NATIVE_INTERNAL_ERROR';
  static const contractValidationFailed = 'CONTRACT_VALIDATION_FAILED';
  static const contractVersionUnsupported = 'CONTRACT_VERSION_UNSUPPORTED';
  static const featureNotImplemented = 'FEATURE_NOT_IMPLEMENTED';
  static const storageNotInitialized = 'STORAGE_NOT_INITIALIZED';
  static const storagePathInvalid = 'STORAGE_PATH_INVALID';
  static const storageIoError = 'STORAGE_IO_ERROR';
  static const storageDataCorrupted = 'STORAGE_DATA_CORRUPTED';
  static const timezoneIdInvalid = 'TIMEZONE_ID_INVALID';
  static const timezoneDatabaseUnavailable = 'TIMEZONE_DATABASE_UNAVAILABLE';
  static const eventTitleEmpty = 'EVENT_TITLE_EMPTY';
  static const eventTimeInvalid = 'EVENT_TIME_INVALID';
  static const eventNotFound = 'EVENT_NOT_FOUND';
  static const eventDeleteScopeInvalid = 'EVENT_DELETE_SCOPE_INVALID';
  static const recurrenceRuleInvalid = 'RECURRENCE_RULE_INVALID';
  static const recurrenceTargetInvalid = 'RECURRENCE_TARGET_INVALID';
  static const allDayRecurringReminderNotSupported =
      'ALL_DAY_RECURRING_REMINDER_NOT_SUPPORTED';
  static const occurrenceNotFound = 'OCCURRENCE_NOT_FOUND';
  static const occurrenceOperationInvalid = 'OCCURRENCE_OPERATION_INVALID';
  static const recurrenceRevisionConflict = 'RECURRENCE_REVISION_CONFLICT';
  static const reminderTimeInvalid = 'REMINDER_TIME_INVALID';
  static const reminderTargetNotFound = 'REMINDER_TARGET_NOT_FOUND';
  static const reminderNotFound = 'REMINDER_NOT_FOUND';
  static const reminderMethodInvalid = 'REMINDER_METHOD_INVALID';
  static const reminderIdempotencyConflict = 'REMINDER_IDEMPOTENCY_CONFLICT';
  static const reminderScheduleConflict = 'REMINDER_SCHEDULE_CONFLICT';
  static const reminderSnoozeNotAllowed = 'REMINDER_SNOOZE_NOT_ALLOWED';
  static const deliveryAttemptInvalid = 'DELIVERY_ATTEMPT_INVALID';
  static const recoveryBatchConflict = 'RECOVERY_BATCH_CONFLICT';
  static const notificationDeliveryFailed = 'NOTIFICATION_DELIVERY_FAILED';
  static const notificationInitializationFailed =
      'NOTIFICATION_INITIALIZATION_FAILED';
  static const habitTitleEmpty = 'HABIT_TITLE_EMPTY';
  static const habitNotFound = 'HABIT_NOT_FOUND';
  static const habitTargetDeleted = 'HABIT_TARGET_DELETED';
  static const habitUpdateConflict = 'HABIT_UPDATE_CONFLICT';
  static const habitDateRangeInvalid = 'HABIT_DATE_RANGE_INVALID';
  static const habitChallengeTooLong = 'HABIT_CHALLENGE_TOO_LONG';
  static const habitTargetInvalid = 'HABIT_TARGET_INVALID';
  static const habitTargetLocked = 'HABIT_TARGET_LOCKED';
  static const habitStartDateLocked = 'HABIT_START_DATE_LOCKED';
  static const habitAlreadyEnded = 'HABIT_ALREADY_ENDED';
  static const habitNotStarted = 'HABIT_NOT_STARTED';
  static const habitEndNotEarly = 'HABIT_END_NOT_EARLY';
  static const habitCheckInDateOutOfRange = 'HABIT_CHECK_IN_DATE_OUT_OF_RANGE';
  static const habitCheckInFutureDate = 'HABIT_CHECK_IN_FUTURE_DATE';
  static const habitCheckInNotFound = 'HABIT_CHECK_IN_NOT_FOUND';
  static const habitDailyStatusRangeInvalid =
      'HABIT_DAILY_STATUS_RANGE_INVALID';
  static const habitDailyStatusRangeTooLarge =
      'HABIT_DAILY_STATUS_RANGE_TOO_LARGE';
  static const habitReminderConfigInvalid = 'HABIT_REMINDER_CONFIG_INVALID';
  static const habitNotificationActionExpired =
      'HABIT_NOTIFICATION_ACTION_EXPIRED';
  static const habitNotificationActionIdentityMismatch =
      'HABIT_NOTIFICATION_ACTION_IDENTITY_MISMATCH';
  static const habitReconciliationCursorInvalid =
      'HABIT_RECONCILIATION_CURSOR_INVALID';
  static const habitReconciliationConflict = 'HABIT_RECONCILIATION_CONFLICT';
  static const habitStatisticsOverflow = 'HABIT_STATISTICS_OVERFLOW';
  static const appearanceColorTokenInvalid = 'APPEARANCE_COLOR_TOKEN_INVALID';
  static const appearanceStorageFailed = 'APPEARANCE_STORAGE_FAILED';
  static const categoryNameEmpty = 'CATEGORY_NAME_EMPTY';
  static const categoryNotFound = 'CATEGORY_NOT_FOUND';
  static const categorySortOrderExhausted = 'CATEGORY_SORT_ORDER_EXHAUSTED';
  static const anniversaryTitleEmpty = 'ANNIVERSARY_TITLE_EMPTY';
  static const anniversaryDateInvalid = 'ANNIVERSARY_DATE_INVALID';
  static const anniversaryCalendarUnsupported =
      'ANNIVERSARY_CALENDAR_UNSUPPORTED';
  static const anniversaryNotFound = 'ANNIVERSARY_NOT_FOUND';
  static const anniversaryUpdateConflict = 'ANNIVERSARY_UPDATE_CONFLICT';
  static const anniversaryTargetDeleted = 'ANNIVERSARY_TARGET_DELETED';
  static const anniversaryReminderConfigInvalid =
      'ANNIVERSARY_REMINDER_CONFIG_INVALID';
  static const anniversaryReminderTemplateDuplicate =
      'ANNIVERSARY_REMINDER_TEMPLATE_DUPLICATE';
  static const anniversaryReminderTemplateLimitExceeded =
      'ANNIVERSARY_REMINDER_TEMPLATE_LIMIT_EXCEEDED';
  static const anniversaryOccurrenceRangeInvalid =
      'ANNIVERSARY_OCCURRENCE_RANGE_INVALID';
  static const anniversaryOccurrenceRangeTooLarge =
      'ANNIVERSARY_OCCURRENCE_RANGE_TOO_LARGE';
  static const anniversaryOccurrenceFilterInvalid =
      'ANNIVERSARY_OCCURRENCE_FILTER_INVALID';
  static const anniversaryOccurrenceCursorInvalid =
      'ANNIVERSARY_OCCURRENCE_CURSOR_INVALID';
  static const anniversaryOccurrenceCursorExpired =
      'ANNIVERSARY_OCCURRENCE_CURSOR_EXPIRED';
  static const anniversaryOccurrenceStale = 'ANNIVERSARY_OCCURRENCE_STALE';
  static const anniversaryReminderOccurrenceExpired =
      'ANNIVERSARY_REMINDER_OCCURRENCE_EXPIRED';
  static const anniversaryAggregateMembershipConflict =
      'ANNIVERSARY_AGGREGATE_MEMBERSHIP_CONFLICT';
  static const calendarRangeInvalid = 'CALENDAR_RANGE_INVALID';
  static const calendarRangeTooLarge = 'CALENDAR_RANGE_TOO_LARGE';
  static const calendarSnapshotInvalid = 'CALENDAR_SNAPSHOT_INVALID';
  static const calendarSnapshotExpired = 'CALENDAR_SNAPSHOT_EXPIRED';
  static const calendarCursorInvalid = 'CALENDAR_CURSOR_INVALID';
  static const calendarCursorQueryMismatch = 'CALENDAR_CURSOR_QUERY_MISMATCH';
  static const calendarWorkflowCommitFailed = 'CALENDAR_WORKFLOW_COMMIT_FAILED';
  static const calendarWorkflowRecoveryFailed =
      'CALENDAR_WORKFLOW_RECOVERY_FAILED';
  static const schedulerReconciliationPending =
      'SCHEDULER_RECONCILIATION_PENDING';
  static const searchQueryInvalid = 'SEARCH_QUERY_INVALID';
  static const searchCursorInvalid = 'SEARCH_CURSOR_INVALID';
  static const searchCursorQueryMismatch = 'SEARCH_CURSOR_QUERY_MISMATCH';
  static const searchCursorExpired = 'SEARCH_CURSOR_EXPIRED';
  static const searchHistoryConflict = 'SEARCH_HISTORY_CONFLICT';
  static const searchHistoryStorageFailed = 'SEARCH_HISTORY_STORAGE_FAILED';
  static const aiExtractionFailed = 'AI_EXTRACTION_FAILED';
  static const syncConflict = 'SYNC_CONFLICT';
  static const syncOperationInvalid = 'SYNC_OPERATION_INVALID';
  static const secureTokenNotFound = 'SECURE_TOKEN_NOT_FOUND';
  static const secureTokenStorageFailed = 'SECURE_TOKEN_STORAGE_FAILED';
  static const secureTokenCorrupted = 'SECURE_TOKEN_CORRUPTED';
  static const permissionDenied = 'PERMISSION_DENIED';
  static const alarmScheduleFailed = 'ALARM_SCHEDULE_FAILED';
  static const alarmCancelFailed = 'ALARM_CANCEL_FAILED';
  static const notificationPermissionDenied = 'NOTIFICATION_PERMISSION_DENIED';
  static const exactAlarmPermissionDenied = 'EXACT_ALARM_PERMISSION_DENIED';
  static const ringCapabilityUnavailable = 'RING_CAPABILITY_UNAVAILABLE';
  static const ringSettingsConflict = 'RING_SETTINGS_CONFLICT';
  static const ringSettingsStorageFailed = 'RING_SETTINGS_STORAGE_FAILED';
  static const ringSettingsCorrupted = 'RING_SETTINGS_CORRUPTED';
  static const ringSessionNotFound = 'RING_SESSION_NOT_FOUND';
  static const ringSessionConflict = 'RING_SESSION_CONFLICT';
  static const ringItemNotFound = 'RING_ITEM_NOT_FOUND';
  static const ringtonePickerFailed = 'RINGTONE_PICKER_FAILED';
  static const ringControlNotificationFailed =
      'RING_CONTROL_NOTIFICATION_FAILED';
  static const ringOutputUnavailable = 'RING_OUTPUT_UNAVAILABLE';
  static const unsupportedReminderMethod = 'UNSUPPORTED_REMINDER_METHOD';
  static const reminderAlreadyConsumed = 'REMINDER_ALREADY_CONSUMED';
  static const reminderNotDue = 'REMINDER_NOT_DUE';
  static const reminderNotDeliverable = 'REMINDER_NOT_DELIVERABLE';

  static const values = {
    nativeInternalError,
    contractValidationFailed,
    contractVersionUnsupported,
    featureNotImplemented,
    storageNotInitialized,
    storagePathInvalid,
    storageIoError,
    storageDataCorrupted,
    timezoneIdInvalid,
    timezoneDatabaseUnavailable,
    eventTitleEmpty,
    eventTimeInvalid,
    eventNotFound,
    eventDeleteScopeInvalid,
    recurrenceRuleInvalid,
    recurrenceTargetInvalid,
    allDayRecurringReminderNotSupported,
    occurrenceNotFound,
    occurrenceOperationInvalid,
    recurrenceRevisionConflict,
    reminderTimeInvalid,
    reminderTargetNotFound,
    reminderNotFound,
    reminderMethodInvalid,
    reminderIdempotencyConflict,
    reminderScheduleConflict,
    reminderSnoozeNotAllowed,
    deliveryAttemptInvalid,
    recoveryBatchConflict,
    notificationDeliveryFailed,
    notificationInitializationFailed,
    habitTitleEmpty,
    habitNotFound,
    habitTargetDeleted,
    habitUpdateConflict,
    habitDateRangeInvalid,
    habitChallengeTooLong,
    habitTargetInvalid,
    habitTargetLocked,
    habitStartDateLocked,
    habitAlreadyEnded,
    habitNotStarted,
    habitEndNotEarly,
    habitCheckInDateOutOfRange,
    habitCheckInFutureDate,
    habitCheckInNotFound,
    habitDailyStatusRangeInvalid,
    habitDailyStatusRangeTooLarge,
    habitReminderConfigInvalid,
    habitNotificationActionExpired,
    habitNotificationActionIdentityMismatch,
    habitReconciliationCursorInvalid,
    habitReconciliationConflict,
    habitStatisticsOverflow,
    appearanceColorTokenInvalid,
    appearanceStorageFailed,
    categoryNameEmpty,
    categoryNotFound,
    categorySortOrderExhausted,
    anniversaryTitleEmpty,
    anniversaryDateInvalid,
    anniversaryCalendarUnsupported,
    anniversaryNotFound,
    anniversaryUpdateConflict,
    anniversaryTargetDeleted,
    anniversaryReminderConfigInvalid,
    anniversaryReminderTemplateDuplicate,
    anniversaryReminderTemplateLimitExceeded,
    anniversaryOccurrenceRangeInvalid,
    anniversaryOccurrenceRangeTooLarge,
    anniversaryOccurrenceFilterInvalid,
    anniversaryOccurrenceCursorInvalid,
    anniversaryOccurrenceCursorExpired,
    anniversaryOccurrenceStale,
    anniversaryReminderOccurrenceExpired,
    anniversaryAggregateMembershipConflict,
    calendarRangeInvalid,
    calendarRangeTooLarge,
    calendarSnapshotInvalid,
    calendarSnapshotExpired,
    calendarCursorInvalid,
    calendarCursorQueryMismatch,
    calendarWorkflowCommitFailed,
    calendarWorkflowRecoveryFailed,
    schedulerReconciliationPending,
    searchQueryInvalid,
    searchCursorInvalid,
    searchCursorQueryMismatch,
    searchCursorExpired,
    searchHistoryConflict,
    searchHistoryStorageFailed,
    aiExtractionFailed,
    syncConflict,
    syncOperationInvalid,
    secureTokenNotFound,
    secureTokenStorageFailed,
    secureTokenCorrupted,
    permissionDenied,
    alarmScheduleFailed,
    alarmCancelFailed,
    notificationPermissionDenied,
    exactAlarmPermissionDenied,
    ringCapabilityUnavailable,
    ringSettingsConflict,
    ringSettingsStorageFailed,
    ringSettingsCorrupted,
    ringSessionNotFound,
    ringSessionConflict,
    ringItemNotFound,
    ringtonePickerFailed,
    ringControlNotificationFailed,
    ringOutputUnavailable,
    unsupportedReminderMethod,
    reminderAlreadyConsumed,
    reminderNotDue,
    reminderNotDeliverable,
  };
}
