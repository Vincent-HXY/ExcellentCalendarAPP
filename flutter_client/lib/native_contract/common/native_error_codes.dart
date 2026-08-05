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
  static const deliveryAttemptInvalid = 'DELIVERY_ATTEMPT_INVALID';
  static const recoveryBatchConflict = 'RECOVERY_BATCH_CONFLICT';
  static const notificationDeliveryFailed = 'NOTIFICATION_DELIVERY_FAILED';
  static const notificationInitializationFailed =
      'NOTIFICATION_INITIALIZATION_FAILED';
  static const habitTitleEmpty = 'HABIT_TITLE_EMPTY';
  static const habitNotFound = 'HABIT_NOT_FOUND';
  static const habitCheckInDuplicated = 'HABIT_CHECK_IN_DUPLICATED';
  static const categoryNameEmpty = 'CATEGORY_NAME_EMPTY';
  static const categoryNotFound = 'CATEGORY_NOT_FOUND';
  static const anniversaryTitleEmpty = 'ANNIVERSARY_TITLE_EMPTY';
  static const anniversaryDateInvalid = 'ANNIVERSARY_DATE_INVALID';
  static const anniversaryNotFound = 'ANNIVERSARY_NOT_FOUND';
  static const searchQueryInvalid = 'SEARCH_QUERY_INVALID';
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
    deliveryAttemptInvalid,
    recoveryBatchConflict,
    notificationDeliveryFailed,
    notificationInitializationFailed,
    habitTitleEmpty,
    habitNotFound,
    habitCheckInDuplicated,
    categoryNameEmpty,
    categoryNotFound,
    anniversaryTitleEmpty,
    anniversaryDateInvalid,
    anniversaryNotFound,
    searchQueryInvalid,
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
    unsupportedReminderMethod,
    reminderAlreadyConsumed,
    reminderNotDue,
    reminderNotDeliverable,
  };
}
