class NativeErrorCodes {
  const NativeErrorCodes._();

  static const nativeInternalError = 'NATIVE_INTERNAL_ERROR';
  static const contractValidationFailed = 'CONTRACT_VALIDATION_FAILED';
  static const contractVersionUnsupported = 'CONTRACT_VERSION_UNSUPPORTED';
  static const eventTitleEmpty = 'EVENT_TITLE_EMPTY';
  static const eventTimeInvalid = 'EVENT_TIME_INVALID';
  static const eventNotFound = 'EVENT_NOT_FOUND';
  static const eventDeleteScopeInvalid = 'EVENT_DELETE_SCOPE_INVALID';
  static const recurrenceRuleInvalid = 'RECURRENCE_RULE_INVALID';
  static const recurrenceTargetInvalid = 'RECURRENCE_TARGET_INVALID';
  static const reminderTimeInvalid = 'REMINDER_TIME_INVALID';
  static const reminderTargetNotFound = 'REMINDER_TARGET_NOT_FOUND';
  static const reminderMethodInvalid = 'REMINDER_METHOD_INVALID';
  static const notificationDeliveryFailed = 'NOTIFICATION_DELIVERY_FAILED';
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
  static const userSettingsInvalid = 'USER_SETTINGS_INVALID';
  static const permissionDenied = 'PERMISSION_DENIED';
  static const alarmScheduleFailed = 'ALARM_SCHEDULE_FAILED';

  static const values = {
    nativeInternalError,
    contractValidationFailed,
    contractVersionUnsupported,
    eventTitleEmpty,
    eventTimeInvalid,
    eventNotFound,
    eventDeleteScopeInvalid,
    recurrenceRuleInvalid,
    recurrenceTargetInvalid,
    reminderTimeInvalid,
    reminderTargetNotFound,
    reminderMethodInvalid,
    notificationDeliveryFailed,
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
    userSettingsInvalid,
    permissionDenied,
    alarmScheduleFailed,
  };
}
